// Icraft 3.36.1 expects each HardOp's weight parameters in contiguous host storage.
#pragma once
#include <icraft-xrt/core/session.h>
#include <icraft-backends/zg330backend/zg330backend.h>
#include <algorithm>
#include <cstring>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <vector>
namespace v3 { namespace model_memory {
using namespace icraft::xir;
using namespace icraft::xrt;
using namespace icraft::xrt::zg330;
inline void require(bool ok,const char* why){if(!ok)throw std::runtime_error(why);}
inline uint64_t logical(const Params& p){
 if(p->mtype.is<ChunkMem>())return p->mtype.cast<ChunkMem>()->offset;
 if(p->mtype.is<ExternalMem>())return p->mtype.cast<ExternalMem>()->addr;
 throw std::runtime_error("unsupported model parameter memory type");
}
// Retain each parameter's bytes, type and logical address; change only its host backing storage.
inline size_t pack(const NetworkView& view){
 size_t groups=0;
 for(auto operation:view->ops){
  auto op=operation.cast<HardOp>();const auto& params=op->params;
  if(params.size()<2)continue;
  uint64_t n=0,origin=logical(params[0]);
  for(const auto& p:params){
   require(p.defined()&&p.hasData(),"model parameter has no host data");
   require(p->mtype.is<ChunkMem>()==params[0]->mtype.is<ChunkMem>(),"mixed parameter memory types");
   if(p->mtype.is<ChunkMem>())require(p->mtype.cast<ChunkMem>()->chunk_id==params[0]->mtype.cast<ChunkMem>()->chunk_id,"mixed weight chunk IDs");
   require(logical(p)>=origin&&logical(p)-origin==n,"non-contiguous logical weights require an adapter");
   require(p.storageBytes()<=256*1024*1024ULL-n,"model weight group exceeds limit");n+=p.storageBytes();
  }
  require(n>0,"empty weight group");auto storage=std::shared_ptr<char[]>(new char[static_cast<size_t>(n)]);
  uint64_t offset=0;
  for(const auto& p:params){auto data=p.data<char>();require(data!=nullptr,"missing parameter bytes");std::memcpy(storage.get()+offset,data.get(),static_cast<size_t>(p.storageBytes()));offset+=p.storageBytes();}
  offset=0;
  for(auto p:params){p.lazySetData(std::shared_ptr<char[]>(storage,storage.get()+offset));offset+=p.storageBytes();}
  ++groups;
 }
 return groups;
}
class Audit {
 struct Owner{MemChunk chunk;uint64_t address,size;};
 struct Block{MemChunk chunk;std::vector<char> expected;uint64_t offset,size,address;int64_t op,value;const char* kind;};
 std::vector<Block> blocks;
public:
 uint64_t bytes=0;
 Audit(const ZG330Backend& backend,const MemRegion& region){
  std::vector<Owner> owners;
  auto add=[&](const MemChunkInfo& m){if(m.defined()&&m->memChunk.defined()&&m->memChunk.isOn(region)){auto c=m->memChunk;owners.push_back({c,c->begin.addr(),c->byte_size});}};
  for(const auto& segment:backend->phy_segment_map){add(segment.second->single_chunk);for(const auto& entry:segment.second->multi_chunk)add(entry.second);}
  std::map<int64_t,HardOpInfo> ordered;
  for(const auto& entry:backend->forward_info->hardop_map)ordered.emplace(entry.first,entry.second);
  auto inspect=[&](int64_t id,const char* kind,const auto& params,uint64_t base,uint64_t segment_size){
   require(!params.empty(),"runtime segment has no model parameters");auto origin=logical(params[0]);uint64_t covered=0;
   for(const auto& p:params){auto n=p.storageBytes();if(!n)continue;
    auto logical_addr=logical(p);require(logical_addr>=origin,"invalid parameter logical offset");auto offset=logical_addr-origin;
    require(offset==covered&&offset<=segment_size&&n<=segment_size-offset,"parameter segment coverage mismatch");covered+=n;
    require(base<=UINT64_MAX-offset,"model address overflow");auto addr=base+offset;const Owner* owner=nullptr;
    for(const auto& candidate:owners)if(addr>=candidate.address&&addr-candidate.address<=candidate.size&&n<=candidate.size-(addr-candidate.address)){owner=&candidate;break;}
    require(owner!=nullptr,"model parameter outside owned allocation");auto expected=p.template data<char>();require(expected!=nullptr,"model expected bytes unavailable");
    blocks.push_back({owner->chunk,std::vector<char>(expected.get(),expected.get()+n),addr-owner->address,n,addr,id,p->v_id,kind});bytes+=n;
   }
   require(covered==segment_size,"model segment is not completely audited");
  };
  for(const auto& entry:ordered){const auto& op=entry.second;
   if(op->weights_size)inspect(entry.first,"weight",op->net_hardop->params,op->weight_phy_addr,op->weights_size);
   if(op->instr_size)inspect(entry.first,"instruction",op->net_hardop->instr,op->instr_phy_addr,op->instr_size);
  }
  require(!blocks.empty(),"no persistent model blocks audited");
 }
 size_t count()const{return blocks.size();}
 void verify(const std::string& stage)const {
  for(const auto& b:blocks){
   // Include surrounding bytes for aligned DMA reads, without leaving the owned chunk.
   auto begin=b.offset&~uint64_t(63),end=b.offset+b.size;
   auto remainder=end%64;if(remainder)end+=std::min<uint64_t>(64-remainder,b.chunk->byte_size-end);
   std::vector<char> actual(static_cast<size_t>(end-begin)),again(actual.size());
   b.chunk.read(actual.data(),begin,actual.size());b.chunk.read(again.data(),begin,again.size());
   require(actual==again,"unstable model memory readback");
   auto offset=b.offset-begin;
   for(uint64_t i=0;i<b.size;++i)if(actual[static_cast<size_t>(offset+i)]!=b.expected[static_cast<size_t>(i)]){
    std::ostringstream error;error<<"MODEL_BYTE_MISMATCH stage="<<stage<<" op="<<b.op<<" kind="<<b.kind<<" value="<<b.value<<" address="<<b.address<<" offset="<<i<<" expected="<<unsigned(static_cast<unsigned char>(b.expected[static_cast<size_t>(i)]))<<" actual="<<unsigned(static_cast<unsigned char>(actual[static_cast<size_t>(offset+i)]));
    throw std::runtime_error(error.str());
   }
  }
 }
};
}}
