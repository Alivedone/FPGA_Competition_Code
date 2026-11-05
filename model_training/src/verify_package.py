"""Verify this module and all system dependencies from the submission manifest."""
from pathlib import Path
import runpy
if __name__=='__main__':
    runpy.run_path(str(Path(__file__).resolve().parents[2]/'verify_submission.py'),run_name='__main__')
