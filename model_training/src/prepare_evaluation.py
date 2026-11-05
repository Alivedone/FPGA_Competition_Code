"""Recreate standardized evaluation frames from the original spectrum MATs."""
import argparse
from pathlib import Path
import numpy as np
from common import ROOT,manifest
from scipy.io import loadmat

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--dataset-root',required=True)
    ap.add_argument('--partition',choices=['development','heldout'],default='development')
    ap.add_argument('--out',type=Path)
    args=ap.parse_args();m=manifest(args.dataset_root)
    dest=args.out or ROOT/('data/evaluation/'+args.partition+'.npz')
    if dest.exists():raise FileExistsError('Keep frozen inputs; select a new output: '+str(dest))
    rows=m['partitions'][args.partition];frames=[];frame_offsets=[0];offsets=[0]
    stats=m['normalization']
    for row in rows:
        cell=loadmat(str(Path(m['dataset_root'])/row['path']),variable_names=['Trace_DPL_Data'])['Trace_DPL_Data']
        x=np.asarray(cell[0][0][0][0],dtype=np.float32)
        if x.shape!=(row['frames'],512) or not np.isfinite(x).all():raise ValueError(row['path'])
        x=np.ascontiguousarray((x-stats['spectrum_mean'])/stats['spectrum_std'],dtype=np.float32)
        frames.append(x);frame_offsets.append(frame_offsets[-1]+len(x));offsets.append(offsets[-1]+len(x)-9)
    dest.parent.mkdir(parents=True,exist_ok=True)
    # Opening a handle prevents numpy from silently appending a second suffix.
    with dest.open('xb') as f:
        np.savez_compressed(f,frames=np.concatenate(frames),frame_offsets=np.asarray(frame_offsets),
            offsets=np.asarray(offsets),sequence_labels=np.asarray([r['label'] for r in rows]))
    print('PREPARED',args.partition,'MATs',len(rows),'windows',offsets[-1],dest)

if __name__=='__main__':main()
