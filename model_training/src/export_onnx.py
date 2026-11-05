"""Export a fresh ONNX; never overwrite the frozen delivered artifact."""
import argparse
from pathlib import Path
import numpy as np
import torch
from common import ROOT,sha,write
from model import load_model
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--checkpoint',type=Path,default=ROOT/'models/best.pt')
    ap.add_argument('--out',type=Path,required=True)
    a=ap.parse_args();a.out=a.out.resolve()
    if a.out.exists():raise FileExistsError(a.out)
    a.out.parent.mkdir(parents=True,exist_ok=True);torch.set_num_threads(4)
    net=load_model(a.checkpoint)
    torch.onnx.export(net,torch.zeros(1,1,10,512),str(a.out),opset_version=11,
        input_names=['spectrum'],output_names=['logits'],do_constant_folding=True)
    import onnx,onnxruntime as ort
    onnx.checker.check_model(onnx.load(str(a.out)))
    so=ort.SessionOptions();so.intra_op_num_threads=4;so.inter_op_num_threads=1
    session=ort.InferenceSession(str(a.out),sess_options=so,providers=['CPUExecutionProvider'])
    x=np.load(str(ROOT/'data/reference_inputs.npy'))[:,None]
    with torch.inference_mode():p=net(torch.from_numpy(x)).numpy()
    q=np.concatenate([session.run(None,{'spectrum':v[None]})[0] for v in x])
    np.testing.assert_allclose(q,p,rtol=2e-4,atol=2e-4)
    write(a.out.with_suffix('.verification.json'),dict(samples=len(x),checkpoint_sha256=sha(a.checkpoint),
        onnx_sha256=sha(a.out),max_abs_error=float(np.max(np.abs(p-q))),
        class_agreement=float(np.mean(p.argmax(1)==q.argmax(1)))))
    print('EXPORTED_AND_VERIFIED',a.out)
if __name__=='__main__':main()
