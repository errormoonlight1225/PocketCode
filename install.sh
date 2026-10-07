#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# License: pocket-code/LICENSE
# Pocket Code bridge installer. Run inside your Codespace project directory.
set -euo pipefail
umask 077
workspace_root="$PWD"
bridge_port=8765
source_dir=""
start_service=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) workspace_root="${2:?Missing root}"; shift 2 ;;
    --port) bridge_port="${2:?Missing port}"; shift 2 ;;
    --source-dir) source_dir="${2:?Missing local source directory}"; shift 2 ;;
    --no-start) start_service=0; shift ;;
    --help) echo 'Usage: bash install.sh [--root DIRECTORY] [--port 8765] [--no-start] [--source-dir CLONE]'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ "$(uname -s)" = Linux ] || { echo '请在 Linux / GitHub Codespaces 中运行。' >&2; exit 1; }
command -v python3 >/dev/null || { echo '需要 Python 3.10+；Codespaces 默认镜像已自带。' >&2; exit 1; }
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else "需要 Python 3.10+")'
install_dir="${POCKET_CODE_HOME:-$HOME/.local/share/pocket-code}"
bin_dir="${POCKET_CODE_BIN_DIR:-$HOME/.local/bin}"
export POCKET_CODE_HOME="$install_dir"
# Python owns atomic downloads, checksum validation and private filesystem writes.
python3 - "$install_dir" "$bin_dir" "$source_dir" <<'PY'
import hashlib,os,pathlib,shlex,stat,sys,tempfile,urllib.request
home=pathlib.Path(sys.argv[1]).expanduser().absolute();bindir=pathlib.Path(sys.argv[2]).expanduser().absolute();source=sys.argv[3]
checks={'pocket_bridge.py': '138f75882fb71d0db671658fec781fe794f8f3b00b921054b4f3caa087858f90', 'pocket_service.py': 'b8fef7f5fddf25a170c95831bc6f388820de1d2a924ce33e3839d6b935e504f6'}
if home.is_symlink():raise SystemExit('安装目录不能是符号链接')
home.mkdir(parents=True,exist_ok=True,mode=0o700)
if home.stat().st_uid!=os.getuid():raise SystemExit('安装目录必须属于当前用户')
home.chmod(0o700);bindir.mkdir(parents=True,exist_ok=True)
payloads={}
for name,digest in checks.items():
 if source:data=(pathlib.Path(source)/'pocket-code/bridge'/name).read_bytes()
 else:
  url='https://raw.githubusercontent.com/errormoonlight1225/PocketCode/main/pocket-code/bridge/'+name
  with urllib.request.urlopen(url,timeout=30) as r:data=r.read(2*1024*1024)
 if hashlib.sha256(data).hexdigest()!=digest:raise SystemExit('校验失败，请重新下载最新 install.sh：'+name)
 payloads[home/name]=data
launcher=bindir/'pocket-code'
payloads[launcher]=('#!/bin/sh\nexport POCKET_CODE_HOME='+shlex.quote(str(home))+'\nexec '+shlex.quote(sys.executable)+' '+shlex.quote(str(home/'pocket_service.py'))+' "$@"\n').encode()
for path,data in payloads.items():
 if path.is_symlink():raise SystemExit('拒绝覆盖符号链接：'+str(path))
 fd,tmp=tempfile.mkstemp(dir=path.parent,prefix='.pocket-install-')
 try:
  with os.fdopen(fd,'wb') as f:f.write(data)
  os.chmod(tmp,0o700 if path==launcher else 0o600);os.replace(tmp,path)
 finally:
  if os.path.exists(tmp):os.unlink(tmp)
print('已安装到：'+str(home))
PY
"$bin_dir/pocket-code" configure --root "$workspace_root" --port "$bridge_port"
if [ "$start_service" = 1 ]; then
  "$bin_dir/pocket-code" start
  if [ -n "${CODESPACE_NAME:-}" ] && command -v gh >/dev/null; then
    if timeout 15 gh codespace ports visibility "$bridge_port:private" -c "$CODESPACE_NAME" >/dev/null 2>&1; then
      echo '已确认 Codespace 转发端口为 Private。'
    else
      echo "请检查 Codespaces → Ports：转发 $bridge_port，并保持 Private。当前凭据可能不允许自动设置。"
    fi
  else
    echo "请检查 Codespaces → Ports：转发 $bridge_port，并保持 Private。"
  fi
fi
printf '\n管理命令：\n  "%s/pocket-code" status\n  "%s/pocket-code" info\n  "%s/pocket-code" restart\n  "%s/pocket-code" stop\n' "$bin_dir" "$bin_dir" "$bin_dir" "$bin_dir"
echo 'Codespace 重启后执行 pocket-code start；如命令未加入 PATH，请使用上面的完整路径。'
