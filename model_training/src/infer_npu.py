"""Standalone final model SDK path; input is already normalized spectrum."""
import argparse,datetime,json,sys,time
from pathlib import Path
import numpy as np
from common import ROOT
from predict import window,decision
class SpectrumNPU:
    def __init__(self):
        if sys.platform!='linux':raise RuntimeError('Run on the actual ZG330 Linux board')
        sys.path.insert(0,'/usr/lib/aarch64-linux-gnu')
        from xir import Network,TensorType
        from xrt import Device,Session,HostDevice,Tensor
        from host_backend import HostBackend
        from zg330backend import ZG330Backend
        net=Network.CreateFromJsonFile(str(ROOT.parent/'model/ResNet18_radar_ZG.json'))
        net.lazyLoadParamsFromFile(str(ROOT.parent/'model/ResNet18_radar_ZG.raw'))
        HostBackend.setThreadsNum(1);self.dev=Device.Open('axi://zg330aiu')
        self.session=Session.Create([ZG330Backend,HostBackend],net.view(0),[self.dev,HostDevice.Default()])
        ZG330Backend(self.session.backends[0]).disableMergeHardOp()
        ZG330Backend(self.session.backends[0]).disableEtmOptimize()
        self.session.apply();self.session.enableTimeProfile(False)
        self.Tensor=Tensor;self.dtype=TensorType(net.inputs()[0].dtype);self.net=net
    def infer(self,x):
        x=np.ascontiguousarray(x,dtype=np.float32)
        if x.shape!=(10,512) or not np.isfinite(x).all():raise ValueError('Expected normalized 10x512 FP32')
        a=time.perf_counter_ns();t=self.Tensor(x.reshape(1,10,512,1),self.dtype)
        b=time.perf_counter_ns();self.dev.reset(1);c=time.perf_counter_ns()
        out=self.session.forward([t])[0]
        if not out.waitForReady(datetime.timedelta(seconds=60)):raise RuntimeError('NPU timeout')
        d=time.perf_counter_ns();z=np.empty(9,dtype='<f4');out.read(z,0,z.nbytes);e=time.perf_counter_ns()
        if not np.isfinite(z).all():raise RuntimeError('Nonfinite model output')
        return z,dict(tensor_build_ms=(b-a)/1e6,reset_ms=(c-b)/1e6,
            forward_wait_ms=(d-c)/1e6,output_read_ms=(e-d)/1e6,request_ms=(e-a)/1e6)
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--input',type=Path,default=ROOT/'data/example_normalized.ftmp')
    ap.add_argument('--raw',action='store_true');ap.add_argument('--start',type=int,default=0)
    ap.add_argument('--warmup',type=int,default=54);ap.add_argument('--requests',type=int,default=1080)
    ap.add_argument('--out',type=Path,required=True)
    a=ap.parse_args();out=a.out.resolve();allowed=(ROOT/'runs').resolve()
    if allowed not in out.parents:raise ValueError('Choose an output directory inside model_training/runs')
    if out.exists():raise FileExistsError(out)
    if a.requests<1 or a.warmup<0:raise ValueError('Invalid request count')
    x=window(a.input.resolve(),a.raw,a.start)
    out.mkdir(parents=True)
    # SDK-generated diagnostics also stay in this run directory.
    import os;os.chdir(str(out))
    import fcntl
    with (allowed/'npu.lock').open('a+b') as lock:
        fcntl.flock(lock.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
        engine=SpectrumNPU()
        for _ in range(a.warmup):engine.infer(x)
        rows=[]
        for _ in range(a.requests):z,t=engine.infer(x);rows.append(t)
        report=decision(z)
        report['timing']={k:dict(mean_ms=float(np.mean([r[k] for r in rows])),
            p95_ms=float(np.percentile([r[k] for r in rows],95))) for k in rows[0]}
        report.update(requests=a.requests,warmup=a.warmup,
            scope='SDK request only; no external PL/network/display; repeated single input, not full benchmark distribution')
        from common import write
        write(out/'report.json',report);write(out/'timing_samples.json',rows)
        print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
