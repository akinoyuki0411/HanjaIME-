#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/select_xcode.sh
source "${SCRIPT_DIR}/scripts/select_xcode.sh"
if ! hanjaime_select_xcode; then
  if [ -t 0 ]; then
    read -r -p "Enter를 누르면 창을 닫습니다..." _ || true
  fi
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "Xcode를 설치하고 한 번 실행해 주세요. Python 3를 찾지 못했습니다."
  exit 1
fi
python3 "${SCRIPT_DIR}/scripts/hanjaime.py" doctor "$@"
status=$?
if [ -t 0 ]; then
  read -r -p "Enter를 누르면 창을 닫습니다..." _ || true
fi
exit "$status"
