"""PC display names and per-task reference labels; never modify wire predictions."""
import json
from pathlib import Path

CLASS_NAMES = ('UAV1', 'UAV2', 'UAV3', 'UAV4', 'Bird', 'Birds', 'Wing Bird', 'Rotate', 'Car')

def display_labels(labels):
    # Only the established nine-class numeric label set has this mapping.
    if list(labels) == [str(i) for i in range(9)]:
        return list(CLASS_NAMES)
    return [str(label) for label in labels]

def truth_from_metadata(meta):
    if not meta or meta.get('category') is None:
        return None
    category = meta['category']
    if not isinstance(category, str) or category not in CLASS_NAMES:
        raise ValueError('配套JSON的category不是已知九类名称')
    return dict(label_set='LSS_HSR_9_v1', class_id=CLASS_NAMES.index(category),
                class_name=category, source='sidecar_json')

def task_truth_name(folder):
    path = Path(folder) / 'task.json'
    if not path.exists():
        return '未知'
    task = json.loads(path.read_text(encoding='utf-8'))
    truth = task.get('ground_truth')
    if truth is None:
        return '未知'
    if not isinstance(truth, dict):
        raise ValueError('任务真实标签格式无效')
    index = truth.get('class_id')
    if (truth.get('label_set') != 'LSS_HSR_9_v1' or type(index) is not int
            or not 0 <= index < len(CLASS_NAMES) or truth.get('class_name') != CLASS_NAMES[index]):
        raise ValueError('任务真实标签编号与名称不一致')
    return CLASS_NAMES[index]
