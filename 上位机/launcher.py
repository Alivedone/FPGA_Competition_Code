"""Preserve startup failures independently of the console window."""
import datetime
import os
from pathlib import Path
import sys
import traceback

ROOT = Path(__file__).resolve().parent


def main():
    os.chdir(ROOT)
    log_dir = ROOT / 'output'
    log_dir.mkdir(parents=True, exist_ok=True)
    with (log_dir / 'startup.log').open('a', encoding='utf-8', buffering=1) as log:
        log.write('\n%s Python=%s\n' % (datetime.datetime.now().isoformat(), sys.executable))
        original_stderr = sys.stderr
        sys.stderr = log
        try:
            import tkinter as tk
            from gui import App
            root = tk.Tk()
            if '--self-test' in sys.argv:
                root.withdraw()
                app = App(root)
                root.update()
                assert root.title() == 'LSS_HSR目标识别'
                app.control.command('shutdown')
                app.control.thread.join(timeout=5)
                root.destroy()
                print('GUI_STARTUP_SELF_TEST_PASS')
                log.write('GUI_STARTUP_SELF_TEST_PASS\n')
            else:
                App(root)
                root.mainloop()
            return 0
        except Exception:
            traceback.print_exc(file=log)
            print('GUI startup failed. See output/startup.log', file=original_stderr)
            return 1
        finally:
            sys.stderr = original_stderr


if __name__ == '__main__':
    raise SystemExit(main())
