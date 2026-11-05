"""Read either legacy 512 FP32 spectra or declared 517 FP32 combined frames."""
import hashlib
import json
import math
import struct
from pathlib import Path
from class_labels import truth_from_metadata


def require(ok, message):
    if not ok:
        raise ValueError(message)


def inspect_source(source):
    source = Path(source)
    size = source.stat().st_size
    sidecar = source.with_suffix('.json')
    meta = json.loads(sidecar.read_text(encoding='utf-8')) if sidecar.exists() else None
    if meta is not None:
        require(isinstance(meta,dict), 'BIN配套JSON必须为对象')
        require(meta.get('schema') == 'LSS_HSR_FRAME' and meta.get('version') == 1,
                '无法识别BIN配套JSON格式')
        require(meta.get('dtype') == 'float32' and meta.get('byte_order') == 'little-endian'
                and meta.get('doppler_bins') == 512 and meta.get('track_features') == 5
                and meta.get('values_per_frame') == 517 and meta.get('bytes_per_frame') == 2068
                and meta.get('layout') == 'frame_major_doppler_then_track'
                and meta.get('data_file') == source.name, '组合BIN格式或文件名不匹配')
        require(meta.get('track_columns') == ['radial_velocity','range','azimuth','height','normalized_snr']
                and meta.get('track_units') == ['m/s','km','degree','m','dB'], '组合BIN轨迹列顺序或单位不匹配')
        preprocessing = meta.get('preprocessing', {})
        require(preprocessing.get('doppler') == 'fixed_training_global_zscore'
                and preprocessing.get('track') == 'none'
                and preprocessing.get('mean') == 137.53303464225368
                and preprocessing.get('std') == 10.262633165907761, '组合BIN需使用已确认的频谱标准化及原始轨迹')
        require(type(meta.get('frame_count')) is int and meta['frame_count'] > 0
                and size == meta['frame_count']*2068, '组合BIN帧数或长度不匹配')
        return dict(frames=size//2068, bytes=(size//2068)*2048, source_bytes=size,
                    format='spectrum_track_517', metadata=meta)
    require(size > 0 and size % 2048 == 0, '纯频谱需完整2048字节帧；517点组合BIN必须保留同名JSON')
    return dict(frames=size//2048, bytes=size, source_bytes=size, format='spectrum_512', metadata=None)


def read_source(source):
    source = Path(source)
    info = inspect_source(source)
    body = source.read_bytes()
    require(len(body) == info['source_bytes'], '输入文件在读取期间改变')
    digest = hashlib.sha256(body).hexdigest()
    tracks = None
    if info['format'] == 'spectrum_track_517':
        require(info['metadata'].get('sha256') == digest, '组合BIN的SHA256不匹配，请勿修改BIN或混用JSON')
        spectra = b''.join(body[i:i+2048] for i in range(0,len(body),2068))
        tracks = b''.join(body[i+2048:i+2068] for i in range(0,len(body),2068))
        require(all(math.isfinite(v[0]) for v in struct.iter_unpack('<f',tracks)), '轨迹含NaN/Inf')
    else:
        spectra = body
    return spectra, tracks, dict(source_format=info['format'], original_file_bytes=len(body),
                                original_sha256=digest,
                                ground_truth=truth_from_metadata(info['metadata']))
