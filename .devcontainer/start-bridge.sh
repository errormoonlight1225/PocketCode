#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# The installer is idempotent and preserves the existing connection key.
# Suppress stdout because the interactive installer prints connection details.
bash "$repo_root/install.sh" --source-dir "$repo_root" --root "$repo_root" --port "${POCKET_BRIDGE_PORT:-8765}" >/dev/null
echo 'Pocket Bridge 已启动；使用 pocket-code info 查看连接信息。'
