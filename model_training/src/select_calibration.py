"""Train-only representative selection; same algorithm as the frozen 54 windows."""
import argparse
from pathlib import Path
import numpy as np
from common import ROOT,manifest,write,sha
from scipy.io import loadmat
def features(x):
    excess = np.maximum(x-x.mean(1, keepdims=True), 0)
    bins = np.linspace(-1, 1, x.shape[1])
    mass = excess.sum()+1e-12
    center = (excess*bins).sum()/mass
    spread = np.sqrt((excess*(bins-center)**2).sum()/mass)
    return np.asarray([x.mean(), x.std(), np.percentile(x, 95)-np.median(x),
        x.max()-np.median(x), np.abs(np.diff(x, axis=0)).mean(),
        np.abs(np.diff(x, axis=1)).mean(), x.argmax(1).std()/512, spread], dtype=float)


def representatives(values, mat_ids, count, seed):
    """Robust-scaled, clipped k-means; nearest real windows, distinct MATs.

    Uses input descriptors only, never model predictions or development scores.
    Clipping reduces selection dominated by extreme outliers.
    """
    median = np.median(values, axis=0)
    scale = np.percentile(values, 75, axis=0)-np.percentile(values, 25, axis=0)
    scale = np.maximum(scale, 1e-8)
    z = np.clip((values-median)/scale, -3, 3)
    rng = np.random.RandomState(seed)
    centers = [z[int(np.argmin((z*z).sum(1)))]]
    for _ in range(1, count):
        distance = ((z[:, None]-np.asarray(centers))**2).sum(2).min(1)
        index = int(rng.choice(len(z), p=distance/distance.sum())) if distance.sum() else len(centers)
        centers.append(z[index])
    centers = np.asarray(centers)
    for _ in range(40):
        assignment = ((z[:, None]-centers)**2).sum(2).argmin(1)
        updated = np.asarray([z[assignment == k].mean(0) if np.any(assignment == k)
                              else centers[k] for k in range(count)])
        if np.allclose(updated, centers, rtol=0, atol=1e-7):
            break
        centers = updated
    selected, used = [], set()
    for center in centers:
        index = next(int(i) for i in np.argsort(((z-center)**2).sum(1), kind='stable')
                     if mat_ids[int(i)] not in used)
        selected.append(index)
        used.add(mat_ids[index])
    return selected, dict(median=median.tolist(), iqr=scale.tolist(), clip=3,
        mean_nearest_selected_distance=float(np.sqrt(((z[:, None]-z[selected])**2).sum(2).min(1)).mean()))


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--dataset-root',required=True);ap.add_argument('--out',type=Path,required=True)
    a=ap.parse_args();m=manifest(a.dataset_root)
    if a.out.exists():raise FileExistsError(a.out)
    a.out.mkdir(parents=True);norm=m['normalization'];candidates=[];windows=[]
    for row in m['partitions']['train']:
        cell=loadmat(str(Path(m['dataset_root'])/row['path']),variable_names=['Trace_DPL_Data'])['Trace_DPL_Data']
        raw=np.asarray(cell[0][0][0][0],dtype=np.float32)
        assert raw.shape==(row['frames'],512) and np.isfinite(raw).all()
        starts=list(range(0,len(raw)-9,5))
        for s in sorted({starts[int(round(q*(len(starts)-1)))] for q in [.1,.5,.9]}):
            x=np.ascontiguousarray((raw[s:s+10]-norm['spectrum_mean'])/norm['spectrum_std'],dtype='<f4')
            candidates.append(dict(source_mat=row['path'],label=row['label'],start_frame_zero_based=s,
                frames=10,partition='train',descriptors=features(x).tolist()));windows.append(x)
    byclass=[]
    for c in range(9):
        ids=[i for i,r in enumerate(candidates) if r['label']==c]
        chosen,_=representatives(np.asarray([candidates[i]['descriptors'] for i in ids]),
            [candidates[i]['source_mat'] for i in ids],6,42+c)
        byclass.append([ids[j] for j in chosen])
    records=[]
    for k in range(6):
        for c in range(9):
            i=byclass[c][k];r=dict(candidates[i]);sample='%03d_class%d'%(len(records),c)
            p=a.out/sample/'0.ftmp';p.parent.mkdir();windows[i].tofile(str(p))
            r.update(sample_id=sample,input_file=p.relative_to(a.out).as_posix(),input_sha256=sha(p));records.append(r)
    frozen=__import__('common').read(ROOT/'data/calibration_selection.json')['records']
    assert all((r['source_mat'],r['start_frame_zero_based'],r['input_sha256'])==
               (q['source_mat'],q['start_frame_zero_based'],q['input_sha256']) for r,q in zip(records,frozen))
    write(a.out/'selection.json',dict(count=54,distinct_mats=len({r['source_mat'] for r in records}),
        matches_frozen_54=True,records=records,heldout_used=False))
    print('CALIBRATION_REPRODUCED 54 windows / 54 distinct training MATs')
if __name__=='__main__':main()
