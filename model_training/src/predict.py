"""Single 10-frame ONNX prediction, or optional raw-spectrum MAT window."""
import argparse,json
from pathlib import Path
import numpy as np
from common import ROOT,read
def window(path,raw=False,start=0):
    path=Path(path)
    if path.suffix.lower()=='.mat':
        from scipy.io import loadmat
        cells=loadmat(str(path),variable_names=['Trace_DPL_Data'])['Trace_DPL_Data']
        x=np.asarray(cells[0][0][0][0],dtype=np.float32)
        if start<0 or start+10>len(x):raise ValueError('Invalid zero-based window start')
        x=x[start:start+10];raw=True
    elif path.suffix.lower()=='.npy':x=np.load(str(path))
    else:x=np.fromfile(str(path),dtype='<f4')
    if x.size!=5120:raise ValueError('Exactly 10x512 scalar values required')
    x=np.asarray(x,dtype=np.float32).reshape(10,512)
    if not np.isfinite(x).all():raise ValueError('Nonfinite spectrum')
    if raw:
        n=read(ROOT/'config/interface.json')['normalization']
        x=(x-n['spectrum_mean'])/n['spectrum_std']
    return np.ascontiguousarray(x,dtype=np.float32)
def decision(z):
    z=np.asarray(z,dtype=np.float32);p=np.exp(z-z.max());p=p/p.sum()
    i=int(p.argmax());classes=read(ROOT/'config/interface.json')['classes']
    return dict(class_index=i,class_name=classes[i],window_confidence=float(p[i]),
        probabilities=p.tolist(),logits=z.tolist(),scope='one 10-frame window')
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--input',type=Path,default=ROOT/'data/example_normalized.ftmp')
    ap.add_argument('--raw',action='store_true',help='Normalize numeric input once; MAT is always raw')
    ap.add_argument('--start',type=int,default=0,help='Zero-based MAT start frame')
    a=ap.parse_args()
    import onnxruntime as ort
    so=ort.SessionOptions();so.intra_op_num_threads=4;so.inter_op_num_threads=1
    s=ort.InferenceSession(str(ROOT/'models/ResNet18_radar.onnx'),sess_options=so,providers=['CPUExecutionProvider'])
    z=s.run(None,{'spectrum':window(a.input,a.raw,a.start).reshape(1,1,10,512)})[0][0]
    print(json.dumps(decision(z),ensure_ascii=False,indent=2))
if __name__=='__main__':main()
