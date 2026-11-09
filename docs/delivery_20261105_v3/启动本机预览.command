#!/bin/zsh
set -e
cd -- "${0:A:h}"
if [[ ! -x .preview-venv/bin/python ]]; then
  preview_ca="$(python3 -c 'import certifi; print(certifi.where())' 2>/dev/null || true)"
  if [[ -n "$preview_ca" && -f "$preview_ca" ]]; then export PIP_CERT="$preview_ca"; fi
  python3 -m venv .preview-venv
  .preview-venv/bin/python -m pip install --index-url https://pypi.org/simple -r requirements-preview.txt
fi
exec .preview-venv/bin/python preview.py
