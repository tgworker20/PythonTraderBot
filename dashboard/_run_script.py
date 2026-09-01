# -*- coding: utf-8 -*-
"""Bootstrap runner for the author's scripts (portable-Python compatible).

The Windows embeddable Python runs in isolated mode because of its ._pth
file: the folder of the script is NOT added to sys.path. That breaks the
author's local imports (e.g. "from Meta import *" next to the script).

This wrapper restores normal Python behaviour: it inserts the script's
folder at the front of sys.path and then runs the script exactly as if
it had been started directly ("__main__"). The author's code is not
modified in any way.

Usage:  python _run_script.py <script.py> [extra args...]
"""
import sys
from pathlib import Path


def main():
    if len(sys.argv) < 2:
        print("usage: python _run_script.py <script.py> [args...]", file=sys.stderr)
        return 2
    script = Path(sys.argv[1]).resolve()
    if not script.exists():
        print(f"script not found: {script}", file=sys.stderr)
        return 2

    # normal python puts the script's folder first on sys.path - restore that
    sys.path.insert(0, str(script.parent))

    import runpy
    sys.argv = [str(script)] + list(sys.argv[2:])
    runpy.run_path(str(script), run_name="__main__")
    return 0


if __name__ == "__main__":
    sys.exit(main())
