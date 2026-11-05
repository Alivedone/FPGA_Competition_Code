"""Check distribution file sizes and SHA256; standard library only."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parent

def main():
    manifest=json.loads((ROOT/'SUBMISSION_MANIFEST.json').read_text(encoding='utf-8'))
    for relative,info in manifest['files'].items():
        p=(ROOT/relative).resolve()
        if ROOT not in p.parents or not p.is_file():raise ValueError('Missing or unsafe file: '+relative)
        if p.stat().st_size!=info['bytes']:raise ValueError('Size mismatch: '+relative)
        h=hashlib.sha256()
        with p.open('rb') as f:
            for b in iter(lambda:f.read(4*1024*1024),b''):h.update(b)
        if h.hexdigest()!=info['sha256']:raise ValueError('Hash mismatch: '+relative)
    print('SUBMISSION_VERIFIED',len(manifest['files']),'files; final ResNet18; no hardware executed')

if __name__=='__main__':main()
