"""Verify CPU hot paths alone use O2 and NPU entry points remain O0."""
import json, shlex, sys
from pathlib import Path

records=json.loads(Path(sys.argv[1]).read_text())
hot=[];main=[]
for row in records:
    args=row.get('arguments') or shlex.split(row['command'])
    opts=[a for a in args if a.startswith('-O') or a in ['/O2','/Od']]
    file=Path(row['file']).name
    if file=='ps_hotpath.cpp':
        assert opts and opts[-1] in ['-O2','/O2'],row
        assert '-fno-fast-math' in args or '/fp:precise' in args,row
        assert '-fno-lto' in args or '/GL-' in args,row
        hot.append(row)
    if file=='main.cpp':
        assert opts and opts[-1] in ['-O0','/Od'],row
        main.append(row)
assert hot and len(main)==1,'Missing hot path or final main command'
print(json.dumps(dict(passed=True,cpu_hotpath_units=len(hot),main_units_at_O0=len(main),compile_database=sys.argv[1])))
