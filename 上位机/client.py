"""PC-only V3 TCP client. Run from PowerShell; no SSH/login password."""
import argparse
import json
import math
import socket
import struct
import time
import uuid
import zlib
from pathlib import Path
from input_data import inspect_source, read_source


class TaskFailed(ValueError):
    """Task failed, but a validated service READY has been received."""
    def __init__(self, header, report, dest):
        self.service_ready, self.report, self.dest = header, report, dest
        error = report['server_error']
        super().__init__("%s: %s (stage=%s; board recovered READY)" % (
            error.get('code', 'TASK_FAILED'), error.get('message', 'unknown'), error.get('stage', '?')))


def check(ok, text):
    if not ok:
        raise ValueError(text)


def crc(data):
    return "%08x" % (zlib.crc32(data) & 0xffffffff)


def message(kind, task_id="", **fields):
    return dict(version=1, type=kind, task_id=task_id, payload_bytes=0, **fields)


def encode(h, data=b""):
    h = dict(h, payload_bytes=len(data))
    raw = json.dumps(h, ensure_ascii=True, separators=(",", ":"), allow_nan=False).encode()
    check(0 < len(raw) <= 65536, "header limit")
    return struct.pack("!I", len(raw)) + raw + data


def exact(s, n, timeout):
    out = bytearray(n)
    at, end = 0, time.monotonic() + timeout
    while at < n:
        left = end - time.monotonic()
        check(left > 0, "receive deadline")
        s.settimeout(left)
        k = s.recv_into(memoryview(out)[at:])
        check(k > 0, "connection closed")
        at += k
    return out


def _unique(pairs):
    result = {}
    for k, v in pairs:
        check(k not in result, "duplicate response field")
        result[k] = v
    return result


def receive(s, timeout=120):
    n = struct.unpack("!I", exact(s, 4, timeout))[0]
    check(0 < n <= 65536, "invalid header length")
    h = json.loads(exact(s, n, timeout).decode("utf-8"), object_pairs_hook=_unique)
    check(type(h.get("version")) is int and h["version"] == 1, "invalid version")
    check(isinstance(h.get("type"), str) and isinstance(h.get("task_id"), str), "invalid response")
    size = h.get("payload_bytes")
    check(type(size) is int and 0 <= size <= 16*1024*1024, "invalid payload length")
    return h, exact(s, size, timeout)


def window_count(size, start, windows, stride):
    check(size > 0 and size % 2048 == 0, "input must contain complete 2048-byte frames")
    check(start >= 0 and windows >= 0 and stride > 0, "invalid window parameters")
    available = (size // 2048 - start - 10) // stride + 1
    check(available > 0 and windows <= available, "no requested complete windows")
    return windows or available


def ready(h):
    check(h.get("type") == "READY" and h.get("scope") == "service" and h.get("task_id") == "" and
          h.get("payload_bytes") == 0, "service READY required")
    info = h["model_info"]
    check(info["input"] == dict(bytes=20480, shape=[1, 10, 512, 1], dtype="float32_le"), "unsupported input")
    out = info["output"]
    check(out["dtype"] == "float32_le" and type(out["bytes"]) is int and 0 < out["bytes"] <= 16*1024*1024,
          "unsupported output")
    product = 1
    for d in out["shape"]:
        check(type(d) is int and d > 0, "invalid output shape")
        product *= d
    check(product * 4 == out["bytes"], "output storage/shape mismatch")
    check(type(info["physical_execution"]) is bool, "missing hardware evidence flag")
    check(h["feedback"] in ("serial", "tcp"), "unknown feedback mode")
    return info


def check_classification(values, info, summary):
    """Verify the reported label/score against raw FP32 outputs; not ground-truth accuracy."""
    labels = info.get('labels')
    check(isinstance(labels, list) and len(labels) == len(values) and len(values) > 0 and
          all(isinstance(x, str) for x in labels), 'classification labels/output mismatch')
    check(all(math.isfinite(x) for x in values), 'nonfinite classification output')
    semantics = info.get('output_semantics')
    if semantics == 'logits':
        peak = max(values)
        probabilities = [math.exp(x-peak) for x in values]
        total = sum(probabilities)
        probabilities = [x/total for x in probabilities]
    else:
        check(semantics == 'probabilities' and all(0 <= x <= 1 for x in values) and
              abs(sum(values)-1) <= .01, 'invalid classification probability semantics')
        probabilities = values
    index = max(range(len(probabilities)), key=probabilities.__getitem__)
    check(isinstance(summary, dict) and summary.get('kind') == 'classification' and
          type(summary.get('class_id')) is int and summary['class_id'] == index and
          summary.get('class_name') == labels[index], 'classification summary class mismatch')
    score = summary.get('score')
    check(type(score) in (float, int) and math.isfinite(score) and
          abs(score-probabilities[index]) <= 1e-6, 'classification summary score mismatch')
    return index, probabilities


def submit(s, service_ready, source, output, start=0, windows=1, stride=1, timeout=120,
           task_id=None, fragment=0, on_event=None):
    info = ready(service_ready)
    source = Path(source).resolve()
    check(inspect_source(source)['bytes'] <= service_ready["max_file_bytes"], "file limit")
    data, track_data, source_identity = read_source(source)
    check(len(data) <= service_ready["max_file_bytes"], "file changed/exceeds limit")
    count = window_count(len(data), start, windows, stride)
    check(count <= service_ready["max_windows"], "window limit")
    lo, hi = info["input_range"]
    for (x,) in struct.iter_unpack("<f", data):
        check(math.isfinite(x) and (lo is None or x >= lo) and (hi is None or x <= hi), "invalid input value")
    task_id = task_id or ("task_" + uuid.uuid4().hex)
    check(0 < len(task_id) <= 64 and all(c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" for c in task_id), "invalid task ID")
    dest = Path(output) / task_id
    dest.mkdir(parents=True, exist_ok=False)
    task = message("START", task_id, file_bytes=len(data), frame_count=len(data)//2048,
                   dtype="float32_le", bins_per_frame=512, window_size=10, start_frame=start,
                   windows=windows, stride=stride, crc32=crc(data))
    (dest/"task.json").write_text(json.dumps(dict(task, source_path=str(source), **source_identity), indent=2), encoding="utf-8")
    (dest/"model_info.json").write_text(json.dumps(info, indent=2), encoding="utf-8")
    seen, received_ok, done, failed = 0, False, False, False
    server_error = None
    with (dest/"events.jsonl").open("x", encoding="utf-8") as events, (dest/"windows.tsv").open("x", encoding="utf-8") as tsv:
        tsv.write("window_index\tstart_frame\tbytes\tcrc32\toutput_file\n")

        def next_event():
            h, body = receive(s, timeout)
            events.write(json.dumps(h, ensure_ascii=True, allow_nan=False) + "\n"); events.flush()
            if on_event:
                on_event(h, body)
            return h, body

        s.settimeout(timeout); s.sendall(encode(task))
        h, body = next_event()
        check(h.get("type") == "READY" and h.get("scope") == "upload" and h["task_id"] == task_id and not body,
              "upload rejected: " + str(h))
        wire = encode(message("DATA", task_id), data)
        if fragment:
            check(fragment > 0, "invalid fragment size")
            for i in range(0, len(wire), fragment):
                s.sendall(wire[i:i+fragment])
        else:
            s.sendall(wire)
        while True:
            h, body = next_event()
            check(h["type"] == "RESULT" or not body, "control message contains unexpected body")
            if h["type"] == "READY":
                ready(h)
                if failed:
                    report = dict(passed=False, completed_windows=server_error.get('completed_windows', seen),
                                  received_results=seen, physical_execution=info['physical_execution'],
                                  ready_received=True, server_error=server_error)
                    (dest/'client_report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
                    raise TaskFailed(h, report, dest)
                check(done and received_ok, "premature service READY")
                check(seen == count if service_ready["feedback"] == "tcp" else seen == 0, "missing/extra results")
                report = dict(passed=True, completed_windows=count, received_results=seen,
                              result_bytes_verified=service_ready["feedback"] == "tcp",
                              physical_execution=info["physical_execution"], ready_received=True)
                if info["model_kind"] == "classification":
                    report["classification_summary_verified"] = service_ready["feedback"] == "tcp"
                    report["classification_accuracy_verified"] = False
                (dest/"client_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
                return h, report, dest
            check(h["task_id"] == task_id, "response task mismatch")
            if h["type"] == "ERROR":
                failed = True
                server_error = h
                check(not h["requires_restart"], "board requires restart: " + str(h))
            elif h["type"] == "RECEIVED":
                check(not received_ok and not done and h["file_bytes"] == len(data) and h["crc32"] == crc(data) and not body,
                      "invalid RECEIVED")
                received_ok = True
            elif h["type"] == "RESULT":
                check(service_ready["feedback"] == "tcp" and received_ok and not done and not failed and seen < count, "unexpected RESULT")
                check(type(h["window_index"]) is int and h["window_index"] == seen and h["start_frame"] == start+seen*stride, "result order/start mismatch")
                out = info["output"]
                check(h["shape"] == out["shape"] and h["dtype"] == out["dtype"] and len(body) == out["bytes"] and crc(body) == h["crc32"], "output metadata/CRC mismatch")
                check(h["physical_execution"] is info["physical_execution"], "hardware evidence mismatch")
                values = [x[0] for x in struct.iter_unpack("<f", body)]
                check(all(math.isfinite(x) for x in values), "nonfinite output")
                if info["model_kind"] == "classification":
                    check_classification(values, info, h.get("summary"))
                if info["model_kind"] == "diagnostic":
                    offset = h["start_frame"] * 2048
                    expected = struct.iter_unpack("<f", data[offset:offset+20480])
                    error = max(abs(y-(.5*x[0]+1)) for x, y in zip(expected, values))
                    check(error <= (2.5 if info["physical_execution"] else 1e-5), "diagnostic output mismatch")
                name = "w10_s%d.output.bin" % h["start_frame"]
                (dest/name).write_bytes(body)
                # Archive the exact immutable upload slice, not a later reread of source.
                input_name = "w10_s%d.input.bin" % h["start_frame"]
                offset = h["start_frame"] * 2048
                input_body = data[offset:offset+20480]
                (dest/input_name).write_bytes(input_body)
                input_record = dict(version=1, start_frame=h['start_frame'], window_size=10,
                                    dtype='float32_le', shape=[1, 10, 512, 1],
                                    payload_bytes=len(input_body), crc32=crc(input_body),
                                    source_crc32=task['crc32'], source_file_bytes=len(data))
                (dest/input_name.replace('.bin', '.json')).write_text(
                    json.dumps(input_record, indent=2), encoding='utf-8')
                if track_data is not None:
                    track_offset = h['start_frame']*20
                    track_body = track_data[track_offset:track_offset+200]
                    track_name = 'w10_s%d.track.bin' % h['start_frame']
                    (dest/track_name).write_bytes(track_body)
                    track_record = dict(version=1, task_id=task_id, start_frame=h['start_frame'],
                        window_size=10, shape=[10,5], dtype='float32_le', payload_bytes=200,
                        crc32=crc(track_body), input_crc32=crc(input_body),
                        source_crc32=task['crc32'], original_sha256=source_identity['original_sha256'],
                        columns=['radial_velocity','range','azimuth','height','normalized_snr'],
                        units=['m/s','km','degree','m','dB'])
                    (dest/track_name.replace('.bin','.json')).write_text(json.dumps(track_record,indent=2),encoding='utf-8')
                tsv.write("%d\t%d\t%d\t%s\t%s\n" % (seen, h["start_frame"], len(body), h["crc32"], name)); tsv.flush()
                seen += 1
            elif h["type"] == "DONE":
                check(received_ok and not done and not failed and h["ready"] is False and
                      type(h["completed_windows"]) is int and h["completed_windows"] == count, "invalid DONE")
                done = True
            else:
                raise ValueError("unexpected message: " + h["type"])


def stop_service(s, timeout=120, on_event=None):
    """Call on the existing task connection; one reader must dispatch all replies.

    A GUI may use the same STOP frame during processing, continuing to consume
    RESULT/DONE until STOPPED. This helper is for idle connections only.
    """
    s.sendall(encode(message("STOP", scope="service", policy="finish_task")))
    accepted = False
    end = time.monotonic() + timeout
    while True:
        left = end-time.monotonic()
        check(left > 0, "STOP deadline; exit not confirmed")
        h, body = receive(s, left)
        if on_event:
            on_event(h, body)
        check(not body and h["task_id"] == "", "invalid STOP response")
        if h["type"] == "ERROR":
            raise ValueError("STOP failed: " + h.get("message", "unknown"))
        check(h.get("scope") == "service" and h.get("policy") == "finish_task", "STOP response scope/policy")
        if h["type"] == "STOPPING":
            accepted = True
        elif h["type"] == "STOPPED":
            check(accepted and h.get("task_buffers_clean") is True, "unsafe STOPPED")
            return h
        else:
            raise ValueError("unexpected STOP reply: " + h["type"])


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--host", default="192.168.1.11"); p.add_argument("--port", type=int, default=5001)
    p.add_argument("--input", type=Path, nargs="+")
    p.add_argument("--output", type=Path)
    p.add_argument("--stop-service", action="store_true", help="stop an idle service without uploading")
    p.add_argument("--stop-after", action="store_true", help="stop after all submitted tasks return READY")
    p.add_argument("--start-frame", type=int, default=0); p.add_argument("--windows", type=int, default=1)
    p.add_argument("--stride", type=int, default=1); p.add_argument("--timeout", type=float, default=120)
    p.add_argument("--fragment-bytes", type=int, default=0, help="PC test option for TCP fragmentation")
    a = p.parse_args()
    check(a.timeout > 0 and 1 <= a.port <= 65535 and a.fragment_bytes >= 0, "invalid client options")
    check((a.stop_service and not a.input and not a.stop_after) or
          (not a.stop_service and a.input and a.output), "provide --input/--output, or --stop-service alone")
    with socket.create_connection((a.host, a.port), timeout=a.timeout) as s:
        h, payload = receive(s, a.timeout); check(not payload, "READY cannot have payload"); ready(h)
        if a.stop_service:
            print(json.dumps(stop_service(s, a.timeout)))
            return
        for source in a.input:
            h, report, dest = submit(s, h, source, a.output, a.start_frame, a.windows, a.stride,
                                     a.timeout, fragment=a.fragment_bytes)
            print(json.dumps(dict(report, saved_to=str(dest)), ensure_ascii=True))
        if a.stop_after:
            print(json.dumps(stop_service(s, a.timeout)))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError) as ex:
        raise SystemExit("V3_CLIENT_FAIL " + str(ex))
