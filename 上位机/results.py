"""Read saved protocol results; validate bytes before presenting probabilities."""
import json
from pathlib import Path
from client import check, crc, check_classification
from plotting import floats, read_plot
from class_labels import display_labels, task_truth_name


def metadata(folder):
    folder = Path(folder)
    info = json.loads((folder / 'model_info.json').read_text(encoding='utf-8'))
    events = [json.loads(s) for s in (folder / 'events.jsonl').read_text(encoding='utf-8').splitlines() if s.strip()]
    windows = [e for e in events if e.get('type') == 'RESULT']
    windows.sort(key=lambda e: e['start_frame'])
    names = ['w10_s%d.output.bin' % e['start_frame'] for e in windows]
    check(len(names) == len(set(names)), '结果事件重复')
    return info, names


def read_result(folder, filename):
    folder = Path(folder)
    info, names = metadata(folder)
    check(filename in names and Path(filename).name == filename, '结果窗口不存在')
    # The shared reader checks event uniqueness, CRC, finite values and summary.
    curves, metric = read_plot(folder, filename)
    if info['model_kind'] == 'diagnostic':
        return dict(kind='diagnostic', curves=curves, metric=metric)
    values = floats((folder / filename).read_bytes())
    check(len(values) * 4 == info['output']['bytes'], '模型输出长度不匹配')
    events = [json.loads(s) for s in (folder / 'events.jsonl').read_text(encoding='utf-8').splitlines() if s.strip()]
    event = next(e for e in events if e.get('type') == 'RESULT' and 'w10_s%d.output.bin' % e['start_frame'] == filename)
    index, probabilities = check_classification(values, info, event.get('summary'))
    names_for_display = display_labels(info['labels'])
    truth = task_truth_name(folder)
    return dict(kind='classification', labels=info['labels'], display_labels=names_for_display, index=index,
                probabilities=probabilities, values=values, semantics=info['output_semantics'],
                metric='发送类别：%s | 预测类别：%s | 最高概率 %.2f%% | CRC / 分类摘要校验通过。' %
                (truth, names_for_display[index], probabilities[index] * 100))


def read_input_window(folder, filename):
    """Validated PC upload snapshot; legacy tasks may use a verified original BIN."""
    folder = Path(folder)
    _, names = metadata(folder)
    check(filename in names and Path(filename).name == filename, '结果窗口不存在')
    events = [json.loads(s) for s in (folder/'events.jsonl').read_text(encoding='utf-8').splitlines() if s.strip()]
    event = next(e for e in events if e.get('type') == 'RESULT' and 'w10_s%d.output.bin' % e['start_frame'] == filename)
    start = event['start_frame']
    check(type(start) is int and start >= 0 and event['window_size'] == 10, '输入窗口范围不正确')
    task = json.loads((folder/'task.json').read_text(encoding='utf-8'))
    check(start >= task['start_frame'] and (start-task['start_frame']) % task['stride'] == 0,
          '输入窗口与任务不匹配')
    input_path = folder/filename.replace('.output.bin', '.input.bin')
    record_path = input_path.with_suffix('.json')
    if input_path.exists() or record_path.exists():
        record = json.loads(record_path.read_text(encoding='utf-8'))
        body = input_path.read_bytes()
        check(record['version'] == 1 and record['start_frame'] == start and record['window_size'] == 10
              and record['shape'] == [1, 10, 512, 1] and record['dtype'] == 'float32_le'
              and record['source_file_bytes'] == task['file_bytes'] and record['source_crc32'] == task['crc32']
              and len(body) == record['payload_bytes'] == 20480 and crc(body) == record['crc32'],
              '输入快照长度/CRC或任务信息不匹配')
        origin = '已校验的实际发送窗口快照（PC保存）'
    else:
        source = Path(task['source_path'])
        data = source.read_bytes()
        check(len(data) == task['file_bytes'] and crc(data) == task['crc32'],
              '旧任务原始BIN已改变，无法确认频谱对应本次输入')
        body = data[start*2048:(start+10)*2048]
        check(len(body) == 20480, '输入窗口长度不正确')
        origin = '旧任务：已核对完整文件CRC的PC原始BIN'
    values = floats(body)
    return dict(frames=[values[i*512:(i+1)*512] for i in range(10)], start_frame=start, origin=origin)


def read_track_window(folder, filename):
    folder = Path(folder)
    # Validate the paired input window and its connection to the task first.
    window = read_input_window(folder, filename)
    start = window['start_frame']
    task = json.loads((folder/'task.json').read_text(encoding='utf-8'))
    path = folder/('w10_s%d.track.bin' % start)
    record_path = path.with_suffix('.json')
    if not path.exists() and not record_path.exists():
        return None  # Legacy spectral-only tasks have no recorded track.
    record = json.loads(record_path.read_text(encoding='utf-8'))
    body = path.read_bytes()
    input_body = (folder/filename.replace('.output.bin','.input.bin')).read_bytes()
    check(record['version'] == 1 and record['task_id'] == task['task_id']
          and record['start_frame'] == start and record['window_size'] == 10
          and record['shape'] == [10,5] and record['dtype'] == 'float32_le'
          and record['payload_bytes'] == len(body) == 200 and record['crc32'] == crc(body)
          and record['input_crc32'] == crc(input_body) and record['source_crc32'] == task['crc32']
          and record['original_sha256'] == task['original_sha256'], '轨迹快照与输入窗口的关联校验失败')
    values = floats(body)
    rows = [values[i*5:(i+1)*5] for i in range(10)]
    check(all(row[1] >= 0 for row in rows), '轨迹距离包含负值')
    return dict(rows=rows, start_frame=start)
