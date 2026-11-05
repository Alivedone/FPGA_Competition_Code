"""Recompute archived numerical results; no training, network or board access."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import numpy as np
from heldout_metrics import classification,evaluate_logits

ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def compare(actual,expected):
    assert actual['confusion_matrix']==expected['confusion_matrix']
    assert abs(actual['accuracy']-expected['accuracy'])<1e-12
    assert abs(actual['macro_f1']-expected['macro_f1'])<1e-12

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--out',type=Path);args=ap.parse_args()
    checks=[]
    manifest=read(ROOT/'PUBLIC_MANIFEST.json')
    for rel,info in manifest['files'].items():
        p=(ROOT/rel).resolve();assert ROOT in p.parents and p.is_file(),rel
        assert p.stat().st_size==info['bytes']
        assert hashlib.sha256(p.read_bytes()).hexdigest()==info['sha256'],rel
    checks.append('public file sizes and SHA256')
    training=[]
    for p in sorted((ROOT/'training_strategies').glob('*/seed*/development_predictions.npz')):
        with np.load(str(p)) as d:
            prob=d['probabilities'];rows=d['row_ids'];labels=d['sequence_labels']
            sums=np.zeros((len(labels),9),dtype=np.float64);np.add.at(sums,rows,prob.astype(np.float64))
            seq=sums/np.bincount(rows,minlength=len(labels))[:,None]
            np.testing.assert_allclose(seq,d['sequence_probabilities'],rtol=0,atol=1e-12)
            wm=classification(d['window_labels'],prob.argmax(1),9);sm=classification(labels,seq.argmax(1),9)
        report=read(p.parent/'metrics.json');compare(wm,report['window']);compare(sm,report['sequence'])
        training.append(p.parent.relative_to(ROOT).as_posix())
    assert len(training)==8;checks.append('8 training runs: window/sequence metrics from saved probabilities')
    for variant in ['A_original54','B_reordered54','C_representative54']:
        folder=ROOT/'calibration'/variant
        with np.load(str(folder/'predictions.npz')) as d:metrics,_=evaluate_logits(d['board_logits'],d['offsets'],d['sequence_labels'],9)
        report=read(folder/'report.json');compare(metrics['window'],report['board_window']);compare(metrics['sequence'],report['board_sequence'])
    checks.append('calibration A/B/C complete-development metrics')
    compared=[]
    for model in ['resnet18','resnet34','resnet50']:
        for part in ['development','heldout']:
            for engine,key,metric_key in [('float','float_logits','onnx'),('host','quant_logits','quantized_host'),('board','board_logits','board')]:
                folder=ROOT/'model_comparison'/('board/'+model+'/'+part if engine=='board' else 'pc/'+model+'/'+engine+'_'+part)
                with np.load(str(folder/'predictions.npz')) as d:metrics,_=evaluate_logits(d[key],d['offsets'],d['sequence_labels'],9)
                report=read(folder/'report.json')[metric_key]
                for kind in ['window','sequence']:compare(metrics[kind],report[kind])
                compared.append(model+'/'+part+'/'+engine)
    assert len(compared)==18;checks.append('3 backbones x 2 partitions x 3 engines')
    summary=read(ROOT/'model_comparison/board/comparison.json')
    for model in ['resnet18','resnet34','resnet50']:
        times=[]
        for n in [1,2,3]:
            p=ROOT/'model_comparison/board'/model/('round'+str(n))/'timing_samples.csv'
            with p.open(encoding='utf-8-sig') as f:times.extend(float(r['request_ms']) for r in csv.DictReader(f))
        expected=next(r for r in summary['models'] if r['model']==model)['timing']['request_ms']
        assert len(times)==expected['count']==3240 and abs(float(np.mean(times))-expected['mean_ms'])<1e-12
    checks.append('9 board latency rounds, 9720 measured requests')
    paired=[]
    for name in ['original_peer','F']:
        folder=ROOT/'npu_optimization/paired_heldout'/name
        with np.load(str(folder/'predictions.npz')) as d:
            z=d['logits'].copy();metrics,_=evaluate_logits(z,d['offsets'],d['sequence_labels'],9)
        report=read(folder/'report.json')['metrics']
        for kind in ['window','sequence']:compare(metrics[kind],report[kind])
        paired.append(z)
    np.testing.assert_array_equal(paired[0],paired[1]);checks.append('original/F paired heldout logits equal')
    report={'status':'passed','checks':checks,'training_runs':len(training),'comparison_evaluations':len(compared),'board_executed':False,'training_executed':False}
    if args.out:
        if args.out.exists():raise FileExistsError(args.out)
        args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))

if __name__=='__main__':main()
