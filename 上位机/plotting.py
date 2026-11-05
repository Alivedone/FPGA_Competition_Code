"""Read an archived task for plots; CRC checks apply before displaying data."""
import json
import math
import struct
from pathlib import Path
from client import check, crc, check_classification
from input_data import read_source


def floats(body):
    check(len(body) > 0 and len(body) % 4 == 0, 'FP32 数据长度不正确')
    values = [v[0] for v in struct.iter_unpack('<f', body)]
    check(all(math.isfinite(v) for v in values), '输出含 NaN/Inf')
    return values


def read_plot(folder, filename):
    folder = Path(folder)
    check(Path(filename).name == filename, '输出文件名无效')
    events = [json.loads(s) for s in (folder/'events.jsonl').read_text(encoding='utf-8').splitlines() if s.strip()]
    matches = [e for e in events if e.get('type') == 'RESULT' and 'w10_s%d.output.bin' % e['start_frame'] == filename]
    check(len(matches) == 1, '结果事件缺失或重复')
    event = matches[0]
    body = (folder/filename).read_bytes()
    check(crc(body) == event['crc32'] and len(body) == event['payload_bytes'], '输出 CRC/长度不匹配')
    values = floats(body)
    info = json.loads((folder/'model_info.json').read_text(encoding='utf-8'))
    if info['model_kind'] != 'diagnostic':
        index, probabilities = check_classification(values, info, event.get('summary'))
        return [('返回原始输出（分类含义见 model_info）', values, '#1767b1')], ('类别编号 %d | score %.4f | CRC / 分类摘要校验通过；分类精度需要真实标签验证。' % (index, probabilities[index]))
    task = json.loads((folder/'task.json').read_text(encoding='utf-8'))
    source, _, _ = read_source(task['source_path'])
    check(len(source) == task['file_bytes'] and crc(source) == task['crc32'], '原始 BIN 已更改，无法比较')
    offset = event['start_frame']*2048
    expected = [.5*x+1 for x in floats(source[offset:offset+20480])]
    check(len(values) == len(expected), '输出尺寸与诊断窗口不匹配')
    errors = [abs(a-b) for a, b in zip(expected, values)]
    limit = 2.5 if info['physical_execution'] else 1e-5
    metric = '第 %d 帧起 | MaxAE %.6g · MAE %.6g · RMSE %.6g | 阈值 %g：%s' % (
        event['start_frame'], max(errors), sum(errors)/len(errors),
        math.sqrt(sum(e*e for e in errors)/len(errors)), limit, '通过' if max(errors) <= limit else '未通过')
    return [('期望：0.5x+1', expected, '#1767b1'), ('返回：NPU/参考输出', values, '#d54238')], metric


def envelope(values, pixels):
    """Keep each bucket's min/max in sample order to preserve narrow spikes."""
    bucket = max(1, math.ceil(len(values)/pixels))
    for start in range(0, len(values), bucket):
        end = min(len(values), start+bucket)
        indices = {start, end-1, min(range(start, end), key=values.__getitem__), max(range(start, end), key=values.__getitem__)}
        for index in sorted(indices):
            yield index, values[index]
