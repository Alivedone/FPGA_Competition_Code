"""Recompute saved accuracy or run final ONNX/NPU over packed real spectra."""
import argparse,json
from pathlib import Path
import numpy as np
from common import ROOT,write
from heldout_metrics import evaluate_logits
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--partition',choices=['development','heldout'],default='heldout')
    ap.add_argument('--engine',choices=['saved_fp32','saved_host','saved_board','onnx','npu'],default='saved_board')
    ap.add_argument('--out',type=Path)
    a=ap.parse_args()
    cache=ROOT/('data/evaluation/'+a.partition+'.npz')
    data=None
    if cache.exists():
        with np.load(str(cache)) as d:data={k:d[k] for k in d.files}
    elif not a.engine.startswith('saved_'):
        raise FileNotFoundError('Prepare inputs with prepare_evaluation.py --partition '+a.partition)
    if a.engine.startswith('saved_'):
        source={'saved_fp32':('pc/float_'+a.partition,'float_logits'),
            'saved_host':('pc/host_'+a.partition,'quant_logits'),
            'saved_board':('board/'+a.partition+'_resnet18','board_logits')}[a.engine]
        with np.load(str(ROOT/('results/'+source[0]+'/predictions.npz'))) as d:
            z=d[source[1]]
            if data is None:data={'offsets':d['offsets'],'sequence_labels':d['sequence_labels']}
            np.testing.assert_array_equal(d['offsets'],data['offsets'])
            np.testing.assert_array_equal(d['sequence_labels'],data['sequence_labels'])
    else:
        if a.engine=='onnx':
            import onnxruntime as ort
            so=ort.SessionOptions();so.intra_op_num_threads=4;so.inter_op_num_threads=1
            session=ort.InferenceSession(str(ROOT/'models/ResNet18_radar.onnx'),sess_options=so,providers=['CPUExecutionProvider'])
            infer=lambda x:session.run(None,{'spectrum':x.reshape(1,1,10,512)})[0][0]
        else:
            from infer_npu import SpectrumNPU
            engine=SpectrumNPU();infer=lambda x:engine.infer(x)[0]
        rows=[]
        for i,(b,e) in enumerate(zip(data['frame_offsets'][:-1],data['frame_offsets'][1:])):
            x=data['frames'][b:e]
            rows.extend(infer(x[s:s+10]) for s in range(len(x)-9))
            if (i+1)%25==0:print(a.engine,i+1,flush=True)
        z=np.asarray(rows,dtype=np.float32)
    metrics,prob=evaluate_logits(z,data['offsets'],data['sequence_labels'],9)
    report=dict(partition=a.partition,engine=a.engine,**metrics,
        sequence_rule='equal mean of all stride-1 window softmax probabilities',
        board_executed=(a.engine=='npu'),saved_historical_board=(a.engine=='saved_board'))
    if a.out:
        if a.out.exists():raise FileExistsError(a.out)
        write(a.out,report)
    print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
