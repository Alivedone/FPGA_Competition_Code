#pragma once
#include "core.hpp"
#include "perf_summary.hpp"
#ifdef LSS_WITH_ICRAFT
#ifdef small
#undef small // Windows RPC macro conflicts with an Icraft SDK parameter name.
#endif
#include "v2_bridge.hpp"
#include "model_params.hpp"
#include "runtime_trace.hpp"
#include "output_guard.hpp"

namespace v3 {
inline Json tensor_spec(const icraft::xir::Value& v) {
    auto t=v->dtype.cast<icraft::xir::TensorType>();check(t->element_dtype.isFP32(),"external plain FP32 I/O required; other types need an adapter");
    std::vector<int64_t> shape;for(auto n:t->shape){check(n>0,"static tensor shape required");shape.push_back(n);}
    return {{"shape",shape},{"dtype","float32_le"},{"bytes",v.storageBytes()}};
}
inline Bound bind_runtime(const icraft::xrt::zg330::ZG330Backend& backend,const icraft::xir::Value& v,const icraft::xrt::MemRegion& region) {
    auto map=backend->forward_info;auto it=map->value_map.find(v->v_id);check(it!=map->value_map.end(),"runtime Value missing");auto info=it->second;
    auto n=v.storageBytes();check(n>0&&n<=MAX_OUTPUT&&!info->is_host&&!info->is_ocm&&info->byte_size==n,"unsupported runtime allocation/storage");
    auto ci=map->memchunk_map.find(v->v_id);check(ci!=map->memchunk_map.end(),"allocation missing");auto chunk=ci->second->memChunk;
    check(chunk.isOn(region),"allocation is not plddr");auto begin=chunk->begin.addr(),addr=info->phy_addr;
    check(addr>=begin&&addr-begin<=chunk->byte_size&&n<=chunk->byte_size-(addr-begin),"Value outside owned allocation");
    check(addr%64==0&&addr<=0x100000000ULL-n,"DDR address outside bridge range");
    icraft::xrt::Tensor tensor(v->dtype.cast<icraft::xir::TensorType>(),chunk,addr-begin);
    check(tensor.data().addr()==addr,"Tensor binding mismatch");return {tensor,chunk,addr,addr-begin};
}
class Hardware final:public Backend {
    std::unique_ptr<Lock> lock;
    icraft::xrt::Device dev;
    icraft::xrt::MemRegion region;
    std::unique_ptr<Bridge> bridge;
    icraft::xir::Network net;
    icraft::xir::NetworkView view;
    icraft::xrt::Session session;
    icraft::xrt::zg330::ZG330Backend backend;
    std::unique_ptr<Bound> input,output;
    std::unique_ptr<model_memory::Audit> model_audit;
    bool audit_each=false;
    // F: callbacks are needed only for explicitly requested detailed tracing.
    bool callbacks_enabled=false;
    RuntimeTrace runtime;
    bool trace_enabled=false;
    bool perf_sync_each=true;
    uint64_t perf_sequence=0;
    void state(const char* stage){if(trace_enabled)runtime.event(stage,{{"layer_count",dev.cast<icraft::xrt::ZG330Device>().layerCount()}});}
    void verify_model(const char* stage){model_audit->verify(stage);std::cerr<<"V3_MODEL_BYTES_PASS stage="<<stage<<" blocks="<<model_audit->count()<<" bytes="<<model_audit->bytes<<std::endl;}
    icraft::xrt::MemChunk udma;
    uint64_t src=0,out_bytes=0,wait_seconds=120;
public:
    explicit Hardware(const Config& cfg,bool mock=false,uint64_t timeout_seconds=120,bool each=false,bool trace=false,bool sync_each=true):audit_each(each),callbacks_enabled(trace),runtime(trace,false,timeout_seconds),trace_enabled(trace),wait_seconds(timeout_seconds) {
        if(!mock) {
#if !defined(__linux__) || !defined(__aarch64__)
            throw Error("hardware execution requires AArch64 Linux");
#endif
        }
        perf_sync_each=false; // F uses SDK scheduling and the final returned Tensor wait.
        net=icraft::xir::Network::CreateFromJsonFile(cfg.json.string());net.loadParamsFromFile(cfg.weights.string());
        check(net.inputs().size()==1&&net.outputs().size()==1,"only one input/output supported");
        info={{"backend",mock?"mock_binding":"hardware"},{"physical_execution",!mock},
              {"input",tensor_spec(net.inputs()[0])},{"output",tensor_spec(net.outputs()[0])}};
        validate_info(info,cfg);out_bytes=net.outputs()[0].storageBytes();
        view=net.view(1,static_cast<int64_t>(net->ops.size())-1);
        check(view.inputs().size()==1&&view.outputs().size()==1,"unexpected model view boundary");
        check(tensor_spec(view.inputs()[0])==info["input"]&&tensor_spec(view.outputs()[0])==info["output"],"view/model interface mismatch");
        auto packed_groups=model_memory::pack(view);
        uint64_t instructions=0;for(auto op:view->ops){check(op.is<icraft::xir::HardOp>(),"host fallback forbidden");for(auto p:op.cast<icraft::xir::HardOp>()->instr)instructions+=p.storageBytes();}
        check(instructions>0,"no hardware instructions");
        if(!mock)lock=std::make_unique<Lock>(); // V2 and V3 share the same interprocess hardware lock.
        dev=icraft::xrt::Device::Open(mock?"mock://zg330":"axi://zg330aiu?npu=0x40000000&dma=0x80000000");
        (void)dev.cast<icraft::xrt::ZG330Device>();region=dev.getMemRegion("plddr");
        if(!mock)bridge=std::make_unique<Bridge>(dev);
        session=icraft::xrt::Session::Create<icraft::xrt::zg330::ZG330Backend>(view,{dev});
        backend=session->backends[0].cast<icraft::xrt::zg330::ZG330Backend>();
        backend.ocmOptimize(icraft::xrt::zg330::OcmOpt::None);backend.disableEtmOptimize();backend.disableMergeHardOp();session.apply();
        check(!session.getForwards().empty(),"empty hardware forward");
        for(auto& op:session.getForwards())check(std::get<1>(op).is<icraft::xrt::zg330::ZG330Backend>(),"host fallback forbidden");
        input=std::make_unique<Bound>(bind_runtime(backend,view.inputs()[0],region));
        output=std::make_unique<Bound>(bind_runtime(backend,view.outputs()[0],region));
        check(input->address+WINDOW<=output->address||output->address+out_bytes<=input->address,"input/output overlap");
        // I/O poisoning and cleanup must never overlap persistent weights/instructions.
        auto overlaps=[](uint64_t a,uint64_t n,uint64_t b,uint64_t m){return n&&m&&(a<=b?b-a<n:a-b<m);};
        for(const auto& entry:backend->forward_info->hardop_map) {
            const auto& op=entry.second;
            for(const auto& io:{std::make_pair(input->address,uint64_t(WINDOW)),std::make_pair(output->address,out_bytes)}) {
                if(op->weights_size)check(!overlaps(io.first,io.second,op->weight_phy_addr,op->weights_size),"I/O buffer overlaps persistent model weights");
                if(op->instr_size)check(!overlaps(io.first,io.second,op->instr_phy_addr,op->instr_size),"I/O buffer overlaps model instructions");
            }
        }
        info["binding"]={{"input_address",input->address},{"input_bytes",WINDOW},
                         {"output_address",output->address},{"output_bytes",out_bytes},
                         {"persistent_overlap_checked",true},{"output_wait_enabled",true}};
        info["binding"]["packed_weight_groups"]=packed_groups;
        info["binding"]["model_audit_each_window"]=audit_each;
        model_audit=std::make_unique<model_memory::Audit>(backend,region);
        info["binding"]["runtime_revision"]="r04_op_sync";
        info["binding"]["sync_each_op"]=perf_sync_each;
        info["binding"]["requested_sync_each_op"]=sync_each;
        info["binding"]["npu_policy"]="F";
        info["binding"]["sjp_npu_reset_before_forward"]=1;
        info["binding"]["operator_callbacks_enabled"]=callbacks_enabled;
        info["binding"]["trace_runtime"]=trace;
        if(mock)return;
        if(callbacks_enabled)runtime.attach(session);
        if(trace){Json schedule=Json::array();for(const auto& item:session.getForwards()){auto op=std::get<0>(item);schedule.push_back({{"op_id",op->op_id},{"name",op->name}});}runtime.event("schedule",{{"ops",schedule}});}
        verify_model("after_apply");
        check(backend.precheck(),"model weights/instructions precheck failed before inference");
        std::cerr<<"V3_MODEL_PRECHECK_PASS "<<info["binding"].dump()<<std::endl;

        udma=dev.getMemRegion("udma").malloc(WINDOW,true,64);src=udma->begin.addr();
        check(src%64==0&&src<=0x40000000ULL-WINDOW,"unsupported PS udma address");
    }
    Prediction infer(const Bytes& b)override {
      PerfSummary perf("hardware_window");
      perf.set("sjp_variant","F");
      perf.set("sequence",++perf_sequence);perf.set("audit_model",audit_each);
      perf.set("trace_runtime",trace_enabled);perf.set("sync_each_op",perf_sync_each);
      for(auto key:{"audit_before_ms","input_prepare_ms","pl_transfer_ms","input_verify_ms",
                   "npu_reset_ms","forward_ms","output_wait_ms","output_read_a_ms","output_read_tensor_ms",
                   "output_read_c_ms","audit_after_ms","output_verify_ms"})
          perf.zero(key);
      try {
        check(bridge!=nullptr&&b.size()==WINDOW,"hardware/window unavailable");
        if(callbacks_enabled)runtime.begin();
        state("before_window");
        if(audit_each)perf.run("audit_before_ms",[&]{verify_model("before_window");});
        perf.run("input_prepare_ms",[&]{
        Bytes poison_in(WINDOW,255),poison_out(static_cast<size_t>(out_bytes),255);
        input->chunk.write(input->offset,reinterpret_cast<char*>(poison_in.data()),WINDOW);output->chunk.write(output->offset,reinterpret_cast<char*>(poison_out.data()),out_bytes);
        Bytes source=b;udma.write(0,reinterpret_cast<char*>(source.data()),WINDOW);wipe(source);
        });
        perf.run("pl_transfer_ms",[&]{bridge->transfer(src,input->address);});
        Prediction p{Bytes(static_cast<size_t>(out_bytes)),Bytes(WINDOW)};
        perf.run("input_verify_ms",[&]{
        input->chunk.read(reinterpret_cast<char*>(p.pl_input.data()),input->offset,WINDOW);
        check(p.pl_input==b,"PL-produced model input differs from source window");
        });
        std::cerr<<"V3_PL_INPUT_PASS bytes="<<WINDOW<<std::endl;
        // Use the SDK-returned Tensor, which carries its completion check function.
        // A manually constructed Tensor is ready by default and has no such callback.
        state("before_forward");
        // Same per-forward SDK reset as validated SJP F; PL bridge is unchanged.
        perf.run("npu_reset_ms",[&]{dev.reset(1);});
        auto forward_start=Clock::now();
        auto returned=perf.run("forward_ms",[&]{return session.forward({input->tensor});});
        if(trace_enabled)runtime.event("forward_returned",{{"forward_ms",RuntimeTrace::ms(forward_start)},{"post_count",runtime.post_count}});
        state("after_forward");
        check(returned.size()==1,"unexpected runtime output count");
        check(returned[0].chunk().isOn(region)&&returned[0].data().addr()==output->address,
              "runtime output Tensor is not the audited DDR buffer");
        if(trace_enabled)runtime.event("output_tensor",{{"address",returned[0].data().addr()},{"offset",returned[0].offset()},{"expected_address",output->address}});
        auto wait_start=Clock::now();
        perf.run("output_wait_ms",[&]{check(returned[0].waitForReady(std::chrono::seconds(wait_seconds)),"NPU output readiness timeout");});
        if(trace_enabled)runtime.event("output_ready",{{"wait_ms",RuntimeTrace::ms(wait_start)}});
        state("after_output_wait");
        if(callbacks_enabled)runtime.end();
        check(backend->forward_info->value_map.at(view.inputs()[0]->v_id)->phy_addr==input->address,"runtime moved input");
        check(backend->forward_info->value_map.at(view.outputs()[0]->v_id)->phy_addr==output->address,"runtime moved output");
        Bytes direct_before(static_cast<size_t>(out_bytes)),direct_after(static_cast<size_t>(out_bytes));
        perf.run("output_read_a_ms",[&]{region.read(reinterpret_cast<char*>(direct_before.data()),MemPtr(output->address),out_bytes);});
        auto read_start=Clock::now();
        perf.run("output_read_tensor_ms",[&]{returned[0].read(reinterpret_cast<char*>(p.data.data()),0,out_bytes);});
        perf.run("output_read_c_ms",[&]{region.read(reinterpret_cast<char*>(direct_after.data()),MemPtr(output->address),out_bytes);});
        if(trace_enabled)runtime.event("readback",{{"tensor_crc32",crc(p.data)},{"direct_before_crc32",crc(direct_before)},{"direct_after_crc32",crc(direct_after)},
             {"tensor_all_ff",untouched_output(p.data)},{"direct_before_all_ff",untouched_output(direct_before)},{"direct_after_all_ff",untouched_output(direct_after)},
             {"read_ms",RuntimeTrace::ms(read_start)}});
        state("after_readback");
        if(audit_each)perf.run("audit_after_ms",[&]{verify_model("after_output_read");});
        std::ostringstream trace;trace<<"V3_NPU_OUTPUT crc32="<<crc(p.data)<<" input_crc32="<<crc(b)<<" words=";
        for(size_t i=0;i<std::min<size_t>(p.data.size()/4,16);++i){uint32_t word;std::memcpy(&word,p.data.data()+4*i,4);trace<<" 0x"<<std::hex<<std::setw(8)<<std::setfill('0')<<word;}
        std::cerr<<trace.str()<<std::endl;
        perf.run("output_verify_ms",[&]{verify_hardware_output(p.data,direct_before,direct_after);});
        perf.finish(true);return p;
    }catch(const std::exception& e){throw HardwareFault(e.what());}}
    void clean()override {
      PerfSummary perf("hardware_cleanup");
      perf.set("audit_model",audit_each);
      try {
        perf.run("buffer_clear_and_verify_ms",[&]{
        check(bridge!=nullptr,"no hardware cleanup in mock mode");
        Bytes zero_in(WINDOW,0),zero_out(static_cast<size_t>(out_bytes),0);
        udma.write(0,reinterpret_cast<char*>(zero_in.data()),WINDOW);
        input->chunk.write(input->offset,reinterpret_cast<char*>(zero_in.data()),WINDOW);output->chunk.write(output->offset,reinterpret_cast<char*>(zero_out.data()),out_bytes);
        Bytes in_check(WINDOW),out_check(static_cast<size_t>(out_bytes));
        input->chunk.read(reinterpret_cast<char*>(in_check.data()),input->offset,WINDOW);
        output->chunk.read(reinterpret_cast<char*>(out_check.data()),output->offset,out_bytes);
        check(in_check==zero_in&&out_check==zero_out,"owned A/B cleanup readback mismatch");
        udma.read(reinterpret_cast<char*>(in_check.data()),0,WINDOW);
        check(in_check==zero_in,"owned udma cleanup readback mismatch");
        });
        perf.zero("audit_cleanup_ms");
        if(audit_each)perf.run("audit_cleanup_ms",[&]{verify_model("after_cleanup");});
        perf.finish(true);
    }catch(const std::exception& e){throw HardwareFault(e.what());}}
};
}
#endif
