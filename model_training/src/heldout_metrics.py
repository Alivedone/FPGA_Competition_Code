"""Frozen final-test metrics; labels are used only after inference."""
import numpy as np


PREFIXES=(.25,.5,.75,1.)


def classification(labels,predictions,classes):
    y=np.asarray(labels,dtype=np.int64);p=np.asarray(predictions,dtype=np.int64)
    if y.ndim!=1 or y.shape!=p.shape or not len(y):
        raise ValueError('Nonempty aligned labels/predictions required')
    if np.any(y<0) or np.any(y>=classes) or np.any(p<0) or np.any(p>=classes):
        raise ValueError('Class index out of bounds')
    cm=np.bincount(y*classes+p,minlength=classes*classes).reshape(classes,classes)
    support=cm.sum(1);precision=np.diag(cm)/np.maximum(cm.sum(0),1)
    recall=np.diag(cm)/np.maximum(support,1)
    f1=2*np.diag(cm)/np.maximum(cm.sum(0)+support,1)
    return dict(samples=len(y),correct=int(np.trace(cm)),accuracy=float(np.trace(cm)/len(y)),
        macro_f1=float(f1.mean()),per_class_precision=precision.tolist(),per_class_recall=recall.tolist(),
        per_class_f1=f1.tolist(),support=support.tolist(),confusion_matrix=cm.tolist())


def evaluate_logits(logits,offsets,sequence_labels,classes):
    z=np.asarray(logits);offsets=np.asarray(offsets,dtype=np.int64)
    y=np.asarray(sequence_labels,dtype=np.int64)
    assert offsets.shape==(len(y)+1,) and offsets[0]==0 and offsets[-1]==len(z)
    assert np.all(np.diff(offsets)>0) and z.shape==(int(offsets[-1]),classes) and np.isfinite(z).all()
    # Match the online policy: FP32 window softmax, FP64 equal-weight cumulative sum.
    p=np.exp(z-z.max(1,keepdims=True));p/=p.sum(1,keepdims=True)
    final=[];probs=[];prefixes={'first_window':[]}
    prefixes.update({str(f):[] for f in PREFIXES})
    for a,b in zip(offsets[:-1],offsets[1:]):
        n=int(b-a);cumulative=np.cumsum(p[a:b].astype(np.float64),axis=0)/np.arange(1,n+1)[:,None]
        probs.append(cumulative[-1]);final.append(int(cumulative[-1].argmax()))
        prefixes['first_window'].append(int(cumulative[0].argmax()))
        for f in PREFIXES:
            index=max(0,int(np.ceil(f*n))-1)
            prefixes[str(f)].append(int(cumulative[index].argmax()))
    window_labels=np.repeat(y,np.diff(offsets))
    return dict(window=classification(window_labels,z.argmax(1),classes),
        sequence=classification(y,final,classes),
        cumulative_prefix={key:classification(y,pred,classes) for key,pred in prefixes.items()}),np.asarray(probs)
