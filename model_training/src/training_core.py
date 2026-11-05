"""Final training operations extracted unchanged from validated training code."""
import random
from pathlib import Path
import numpy as np
from scipy.io import loadmat
import torch
from heldout_metrics import classification
def load_spectrum(path):
    # Only the spectrum cell is selected. Track features are never extracted,
    # normalized, cached, passed to a model, or used for sampling/selection.
    cells = loadmat(str(path), variable_names=['Trace_DPL_Data'])['Trace_DPL_Data']
    x = np.asarray(cells[0][0][0][0], dtype=np.float32)
    if x.ndim != 2 or x.shape[1] != 512 or not np.isfinite(x).all():
        raise ValueError('Invalid spectrum: '+str(path))
    return x


def validate_partitions(manifest):
    train = manifest['partitions']['train'];dev = manifest['partitions']['development']
    paths = [r['path'] for r in train+dev]
    if len(paths) != len(set(paths)):
        raise ValueError('Duplicate MAT or train/development overlap')
    if manifest['window'] != 10:
        raise ValueError('This campaign freezes the 10x512 interface')
    if manifest['train_stride'] != 5 or manifest['evaluation_stride'] != 1:
        raise ValueError('Unexpected historical strides')
    classes = len(manifest['classes'])
    for rows in (train, dev):
        if set(r['label'] for r in rows) != set(range(classes)):
            raise ValueError('Every class must be represented in each partition')
        if any(r['frames'] < 10 for r in rows):
            raise ValueError('Short sequence')


class SpectralCache:
    def __init__(self, manifest, partition, device):
        if partition not in ('train', 'development'):
            raise ValueError('Heldout is forbidden in the training campaign')
        self.rows = manifest['partitions'][partition]
        self.classes = len(manifest['classes'])
        norm = manifest['normalization']
        self.mean = norm['spectrum_mean'];self.std = norm['spectrum_std']
        self.normalized = []
        windows, labels, row_ids, starts = [], [], [], []
        stride = 5 if partition == 'train' else 1
        root = Path(manifest['dataset_root'])
        for i, row in enumerate(self.rows):
            raw = load_spectrum(root/row['path'])
            if raw.shape != (row['frames'], 512):
                raise ValueError('Frame count mismatch')
            x = np.ascontiguousarray((raw-self.mean)/self.std, dtype=np.float32)
            self.normalized.append(x)
            for start in range(0, len(x)-9, stride):
                windows.append(x[start:start+10]);labels.append(row['label'])
                row_ids.append(i);starts.append(start)
        self.x = torch.as_tensor(np.stack(windows)[:,None], device=device)
        self.y = torch.as_tensor(labels, dtype=torch.long, device=device)
        self.labels = np.asarray(labels, dtype=np.int64)
        self.row_ids = np.asarray(row_ids, dtype=np.int64)
        self.starts = np.asarray(starts, dtype=np.int64)
        self.sequence_labels = np.asarray([r['label'] for r in self.rows], dtype=np.int64)
        self.offsets = np.r_[0, np.cumsum(np.bincount(self.row_ids, minlength=len(self.rows)))]
        self.class_rows = [np.flatnonzero(self.sequence_labels == c) for c in range(self.classes)]
        self.device = device

    def __len__(self):
        return len(self.labels)

    def balanced_draw(self, rng, count):
        labels = rng.integers(self.classes, size=count)
        rows = np.asarray([rng.choice(self.class_rows[c]) for c in labels])
        starts = np.asarray([rng.integers(len(self.normalized[i])-9) for i in rows])
        x = np.stack([self.normalized[i][s:s+10] for i,s in zip(rows,starts)])[:,None]
        return torch.as_tensor(x, device=self.device), torch.as_tensor(labels, dtype=torch.long, device=self.device), rows, starts


def metrics_from_probabilities(prob, cache):
    sums = np.zeros((len(cache.rows), cache.classes), dtype=np.float64)
    np.add.at(sums, cache.row_ids, prob.astype(np.float64))
    counts = np.diff(cache.offsets)
    seq_prob = sums/counts[:,None]
    window = classification(cache.labels, prob.argmax(1), cache.classes)
    sequence = classification(cache.sequence_labels, seq_prob.argmax(1), cache.classes)
    return dict(window=window, sequence=sequence), seq_prob


@torch.inference_mode()
def evaluate(model, cache, batch_size):
    model.eval()
    prob = torch.cat([model(cache.x[a:a+batch_size]).softmax(1)
                      for a in range(0, len(cache), batch_size)]).cpu().numpy()
    metrics, seq = metrics_from_probabilities(prob, cache)
    return metrics, prob, seq


def seed_all(seed):
    random.seed(seed);np.random.seed(seed);torch.manual_seed(seed)
    if torch.cuda.is_available():torch.cuda.manual_seed_all(seed)

