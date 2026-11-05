"""Single socket owner used by the desktop GUI and integration tests."""
import queue
import socket
import threading
import time
from pathlib import Path

from client import TaskFailed, check, ready, receive, stop_service, submit, window_count
from input_data import inspect_source


def inspect_files(files, start, count, step):
    check(bool(files), '请先添加 BIN 文件')
    rows = []
    for name in files:
        p = Path(name).resolve()
        source_info = inspect_source(p)
        size = source_info['bytes']
        windows = window_count(size, start, count, step)
        rows.append(dict(path=str(p), bytes=size, frames=source_info['frames'], windows=windows,
                         source_bytes=source_info['source_bytes'], source_format=source_info['format']))
    return rows


class Controller:
    def __init__(self):
        self.events = queue.Queue()
        self.stop_pending = threading.Event()
        self.commands = queue.Queue()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def emit(self, kind, **data):
        self.events.put(dict(kind=kind, **data))

    def command(self, kind, **data):
        self.commands.put((kind, data))

    def request_stop(self):
        # No second reader and no control frame inserted into an upload.
        self.stop_pending.set()
        self.command('stop')

    def _run(self):
        sock, header, timeout = None, None, 120
        while True:
            kind, args = self.commands.get()
            try:
                if kind == 'connect':
                    check(sock is None, '连接已经建立')
                    timeout = float(args['timeout'])
                    check(1 <= timeout <= 3600, '超时范围为 1–3600 秒')
                    # A just-closed idle connection may still own the server briefly.
                    # Retry BUSY/connection before START only; never retry a task.
                    deadline = time.monotonic() + min(timeout, 5)
                    while True:
                        sock = socket.create_connection((args['host'], args['port']), timeout)
                        header, body = receive(sock, timeout)
                        if header.get('type') != 'BUSY':
                            break
                        sock.close()
                        sock = None
                        check(header.get('stage') == 'connection' and time.monotonic() < deadline,
                              '服务忙或正在停止，请检查板端状态后重新连接')
                        time.sleep(.15)
                    info = ready(header)
                    check(not body and header['feedback'] == 'tcp', '请启动 TCP 结果反馈服务')
                    self.stop_pending.clear()
                    self.emit('connected', info=info)
                elif kind == 'send':
                    check(sock is not None, '尚未连接')
                    rows = inspect_files(args['files'], args['start'], args['count'], args['step'])
                    succeeded = failed = 0
                    for index, row in enumerate(rows):
                        if self.stop_pending.is_set():
                            self.emit('skipped', count=len(rows)-index)
                            break
                        self.emit('task_start', index=index+1, total=len(rows), **row)
                        try:
                            header, report, dest = submit(
                                sock, header, row['path'], args['output'], args['start'],
                                args['count'], args['step'], timeout,
                                on_event=lambda h, b: self.emit('protocol', header=h))
                        except TaskFailed as exc:
                            header = exc.service_ready
                            failed += 1
                            self.emit('task_failed', report=exc.report, path=str(exc.dest),
                                      source=row['path'], message=str(exc))
                        else:
                            succeeded += 1
                            self.emit('result', report=report, path=str(dest), source=row['path'])
                    self.emit('batch_done', succeeded=succeeded, failed=failed)
                elif kind == 'disconnect':
                    if sock:
                        sock.close()
                    sock, header = None, None
                    self.emit('disconnected')
                elif kind == 'shutdown':
                    if sock:
                        sock.close()
                    return
                elif kind != 'stop':
                    raise ValueError('unknown command')
                if self.stop_pending.is_set():
                    if sock:
                        stopped = stop_service(sock, timeout,
                                               on_event=lambda h, b: self.emit('protocol', header=h))
                        sock.close()
                        sock, header = None, None
                        self.emit('stopped', header=stopped)
                    self.stop_pending.clear()
            except Exception as exc:
                if sock:
                    sock.close()
                sock, header = None, None
                self.stop_pending.clear()
                self.emit('error', message=str(exc))

