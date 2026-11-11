"""Current acceptance entry point; retain verify_revision.py compatibility."""
import runpy
from pathlib import Path
runpy.run_path(str(Path(__file__).with_name('verify_revision.py')), run_name='__main__')
