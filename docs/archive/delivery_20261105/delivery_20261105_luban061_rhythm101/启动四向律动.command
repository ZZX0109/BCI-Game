#!/bin/zsh
cd "$(dirname "$0")"
if [[ -x .venv/bin/python ]]; then
    .venv/bin/python preview.py
elif [[ -n "$NEURALIFE_PYTHON" && -x "$NEURALIFE_PYTHON" ]]; then
    "$NEURALIFE_PYTHON" preview.py
elif python3 -c 'import PySide6' >/dev/null 2>&1; then
    python3 preview.py
else
    echo '请先在本目录安装预览依赖：'
    echo 'python3 -m venv .venv'
    echo '.venv/bin/python -m pip install -r requirements-preview.txt'
    read '?按回车退出'
fi
