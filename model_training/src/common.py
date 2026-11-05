"""All runtime paths are relative to the extracted delivery folder."""
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def read(p): return json.loads(Path(p).read_text(encoding='utf-8'))
def write(p,value):
    p=Path(p);p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p):
    h=hashlib.sha256()
    with Path(p).open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
def manifest(dataset_root=None):
    m=read(ROOT/'config/dataset_manifest.json')
    if dataset_root is not None:
        root=Path(dataset_root).resolve()
        if not (root/'train').is_dir() or not (root/'validation').is_dir():
            raise ValueError('--dataset-root must contain train/ and validation/')
        m['dataset_root']=str(root)
    return m
