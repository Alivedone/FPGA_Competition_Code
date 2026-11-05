"""Final 30-epoch AdamW recipe; training reads spectrum train/development only."""
import argparse,datetime,time
import numpy as np
import torch
from torch import nn
from common import ROOT,read,write,sha,manifest
from model import SpectrumNet as FinalNet
from training_core import SpectralCache,seed_all,evaluate,validate_partitions
class SpectrumNet(FinalNet):
    def __init__(self,name):
        if name!='resnet18':raise ValueError('Final model is ResNet18')
        super().__init__()
def train(name,p,train,dev):
    d=OUT/'training'/name;d.mkdir(parents=True,exist_ok=True)
    if (d/'metrics.json').exists():
        r=read(d/'metrics.json');assert sha(d/'best.pt')==r['checkpoint_sha256'];print('CACHED',name,flush=True);return
    seed_all(42);model=SpectrumNet(name).cuda()
    optimizer=torch.optim.AdamW(model.parameters(),lr=.001,weight_decay=.01)
    scheduler=torch.optim.lr_scheduler.CosineAnnealingLR(optimizer,30,eta_min=.00001)
    loss_fn=nn.CrossEntropyLoss();rng=np.random.default_rng(42)
    history=[];best=-1.;best_epoch=0;best_metrics=None;resume=d/'resume.pt'
    if resume.exists():
        s=torch.load(str(resume),map_location='cuda',weights_only=False)
        assert s['identity']==dict(model=name,protocol_sha256=sha(OUT/'training_protocol.json'))
        model.load_state_dict(s['model']);optimizer.load_state_dict(s['optimizer']);scheduler.load_state_dict(s['scheduler'])
        history=s['history'];best=s['best'];best_epoch=s['best_epoch'];best_metrics=s['best_metrics']
        rng.bit_generator.state=s['numpy_rng'];torch.set_rng_state(s['torch_rng'].cpu());torch.cuda.set_rng_state_all([x.cpu() for x in s['cuda_rng']])
    for epoch in range(len(history)+1,31):
        begin=time.perf_counter();model.train();draw=train.balanced_draw(rng,len(train));total=torch.zeros((),device='cuda')
        lr=optimizer.param_groups[0]['lr']
        for a in range(0,len(train),64):
            x,y=draw[0][a:a+64],draw[1][a:a+64]
            optimizer.zero_grad(set_to_none=True);loss=loss_fn(model(x),y)
            if not torch.isfinite(loss):raise RuntimeError('Nonfinite loss')
            loss.backward();optimizer.step();total+=loss.detach()*len(y)
        metrics,_,_=evaluate(model,dev,64)
        row=dict(epoch=epoch,learning_rate=lr,loss=float(total.cpu())/len(train),epoch_seconds=time.perf_counter()-begin,**metrics)
        history.append(row)
        if metrics['sequence']['macro_f1']>best:
            best=metrics['sequence']['macro_f1'];best_epoch=epoch;best_metrics=metrics
            torch.save(dict(state_dict=model.state_dict(),branch=name+'_spectrum',seed=42,epoch=epoch,
                manifest_sha256=p['manifest_sha256'],strategy='class_then_mat_then_start',input='spectrum_only',track_used=False),d/'best.pt')
        scheduler.step();write(d/'history.json',history)
        temp=d/'resume.pending.pt'
        torch.save(dict(identity=dict(model=name,protocol_sha256=sha(OUT/'training_protocol.json')),
            model=model.state_dict(),optimizer=optimizer.state_dict(),scheduler=scheduler.state_dict(),history=history,
            best=best,best_epoch=best_epoch,best_metrics=best_metrics,numpy_rng=rng.bit_generator.state,
            torch_rng=torch.get_rng_state(),cuda_rng=torch.cuda.get_rng_state_all()),temp)
        temp.replace(resume)
        write(OUT/'training_status.json',dict(status='training',model=name,epoch=epoch,best_epoch=best_epoch,pid=os.getpid(),**metrics))
        print('EPOCH',name,epoch,'loss',round(row['loss'],4),'dev_seq_acc',round(metrics['sequence']['accuracy'],5),
              'dev_seq_f1',round(metrics['sequence']['macro_f1'],5),'best',best_epoch,'seconds',round(row['epoch_seconds'],2),flush=True)
    model.load_state_dict(torch.load(str(d/'best.pt'),map_location='cuda',weights_only=True)['state_dict'])
    final,prob,seq=evaluate(model,dev,64);assert final==best_metrics
    np.savez_compressed(str(d/'development_predictions.npz'),probabilities=prob,sequence_probabilities=seq,
        window_labels=dev.labels,sequence_labels=dev.sequence_labels,row_ids=dev.row_ids)
    write(d/'metrics.json',dict(model=name,seed=42,best_epoch=best_epoch,epochs=30,parameters=sum(v.numel() for v in model.parameters()),
        training_seconds=sum(r['epoch_seconds'] for r in history),checkpoint_sha256=sha(d/'best.pt'),
        input='spectrum_only',track_used=False,heldout_used=False,reloaded_metrics_verified=True,**final))
    resume.unlink();del model,optimizer;torch.cuda.empty_cache();print('DONE',name,best_epoch,final['sequence']['accuracy'],flush=True)


def main():
    global OUT
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--dataset-root',required=True)
    ap.add_argument('--out',type=__import__('pathlib').Path,required=True)
    args=ap.parse_args();OUT=args.out.resolve()
    if OUT==ROOT/'models' or ROOT/'models' in OUT.parents:raise ValueError('Do not overwrite frozen models')
    if not torch.cuda.is_available():raise RuntimeError('CUDA GPU required for matched recipe')
    torch.set_num_threads(4);torch.backends.cudnn.benchmark=False;torch.backends.cudnn.deterministic=True
    torch.backends.cuda.matmul.allow_tf32=False;torch.backends.cudnn.allow_tf32=False
    m=manifest(args.dataset_root);validate_partitions(m);OUT.mkdir(parents=True,exist_ok=True)
    p=dict(config=read(ROOT/'config/training.json'),manifest_sha256=sha(ROOT/'config/dataset_manifest.json'),
        classes=m['classes'],normalization=m['normalization'],track_used=False,heldout_used=False,
        source_sha256={name:sha(ROOT/'src'/name) for name in ['train.py','model.py','training_core.py']})
    target=OUT/'training_protocol.json'
    if target.exists() and read(target)!=p:raise ValueError('Run identity changed; choose a new --out')
    write(target,p)
    train_cache=SpectralCache(m,'train','cuda');dev=SpectralCache(m,'development','cuda')
    assert len(train_cache)==6153 and len(dev)==6836
    train('resnet18',p,train_cache,dev)
if __name__=='__main__':main()
