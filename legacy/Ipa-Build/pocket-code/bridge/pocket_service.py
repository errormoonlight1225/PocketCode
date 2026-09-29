#!/usr/bin/env python3
"""User-owned Linux service manager. No sudo or third-party packages."""
import argparse, fcntl, json, os, pathlib, secrets, signal, subprocess, sys, time, urllib.request
HOME_DIR=pathlib.Path(os.environ.get('POCKET_CODE_HOME',pathlib.Path.home()/'.local/share/pocket-code')).expanduser().absolute()
CONFIG=HOME_DIR/'config.json'; KEY=HOME_DIR/'connection.key'; STATE=HOME_DIR/'process.json'
BRIDGE=HOME_DIR/'pocket_bridge.py'; LOG=HOME_DIR/'service.log'
def private_dir():
    if HOME_DIR.is_symlink(): raise RuntimeError('安装目录不能是符号链接')
    HOME_DIR.mkdir(mode=0o700,parents=True,exist_ok=True)
    if HOME_DIR.stat().st_uid!=os.getuid(): raise RuntimeError('安装目录不属于当前用户')
    HOME_DIR.chmod(0o700)
    for p in [CONFIG,KEY,STATE,LOG,HOME_DIR/'service.lock']:
        if p.is_symlink(): raise RuntimeError('拒绝写入符号链接：'+p.name)
def save(path,value):
    temp=path.with_name(path.name+'.'+secrets.token_hex(6))
    fd=os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    try:
        with os.fdopen(fd,'w') as f: f.write(value);f.flush();os.fsync(f.fileno())
        os.replace(temp,path)
    finally:
        if temp.exists(): temp.unlink()
def read(path):
    try:return json.loads(path.read_text())
    except FileNotFoundError:return None
def config():
    c=read(CONFIG)
    if not c:raise RuntimeError('尚未配置，请重新运行安装脚本')
    return c
def local_request(c,path='health',post=False):
    req=urllib.request.Request(f"http://127.0.0.1:{c['port']}/{path}",data=b'{}' if post else None,headers={'X-Pocket-Key':KEY.read_text().strip(),'Content-Type':'application/json'})
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self,*args):return None
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
    with opener.open(req,timeout=1) as r:return json.load(r)
def healthy(c):
    try:
        j=local_request(c)
        return j.get('version')==2 and j.get('root')==c['root']
    except (OSError,ValueError):return False
def info():
    c=config();print('Pocket Code：'+('正在运行' if healthy(c) else '未运行或未就绪'))
    print('工作区：'+c['root']);print(f"本地服务：http://127.0.0.1:{c['port']}",flush=True)
    name=os.environ.get('CODESPACE_NAME');domain=os.environ.get('GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN','app.github.dev')
    if name:print(f"App 连接地址：https://{name}-{c['port']}.{domain}")
    else:print('未检测到 Codespaces；iOS App 需要 Codespaces HTTPS 私有转发地址。')
    print('App 连接密钥：'+KEY.read_text().strip());print('在 App 登录 GitHub 后填写地址和密钥；不要公开密钥。')
def configure(root,port):
    root=pathlib.Path(root).expanduser().resolve()
    if not root.is_dir():raise RuntimeError('工作区目录不存在')
    if not 1024<=port<=65535:raise RuntimeError('端口必须为 1024–65535')
    c={'root':str(root),'port':port}
    previous=read(CONFIG)
    if previous and healthy(previous) and c!=previous:raise RuntimeError('另一个配置正在运行。先 pocket-code stop，再重新配置。')
    save(CONFIG,json.dumps(c))
    if not KEY.exists():save(KEY,secrets.token_urlsafe(32)+'\n')
    KEY.chmod(0o600)
def start():
    c=config()
    if healthy(c):info();return
    if not BRIDGE.is_file():raise RuntimeError('服务文件缺失，请重新安装')
    with open(LOG,'ab',buffering=0) as log:
        os.chmod(LOG,0o600)
        child=subprocess.Popen([sys.executable,'-u',str(BRIDGE),'--root',c['root'],'--port',str(c['port']),'--key-file',str(KEY),'--quiet-auth'],stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
    for _ in range(50):
        if child.poll() is not None:raise RuntimeError('服务启动失败（可能端口被占用），查看 '+str(LOG))
        if healthy(c):
            save(STATE,json.dumps({'pid':child.pid}));info();return
        time.sleep(0.1)
    child.terminate()
    try:child.wait(timeout=3)
    except subprocess.TimeoutExpired:child.kill();child.wait()
    STATE.unlink(missing_ok=True);raise RuntimeError('启动超时，查看 '+str(LOG))
def stop():
    c=config()
    if not healthy(c):print('服务已经停止或未响应');STATE.unlink(missing_ok=True);return
    local_request(c,'service/stop',True)
    for _ in range(50):
        if not healthy(c):break
        time.sleep(0.1)
    else:raise RuntimeError('服务未及时停止；请检查日志，不会强制终止未知进程')
    STATE.unlink(missing_ok=True);print('服务已停止')
def main():
    if sys.platform!='linux':raise RuntimeError('管理器用于 Linux / GitHub Codespaces')
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('command',choices=['configure','start','stop','restart','status','info']);p.add_argument('--root',default=os.getcwd());p.add_argument('--port',type=int,default=8765);a=p.parse_args();private_dir()
    with open(HOME_DIR/'service.lock','a') as lock:
        os.chmod(HOME_DIR/'service.lock',0o600);fcntl.flock(lock,fcntl.LOCK_EX)
        if a.command=='configure':configure(a.root,a.port)
        elif a.command=='start':start()
        elif a.command=='stop':stop()
        elif a.command=='restart':stop();start()
        elif a.command=='info':info()
        else:
            ok=healthy(config());print('running' if ok else 'stopped');return 0 if ok else 1
    return 0
if __name__=='__main__':
    try:sys.exit(main())
    except (RuntimeError,OSError,ValueError) as e:print('错误：'+str(e),file=sys.stderr);sys.exit(1)
