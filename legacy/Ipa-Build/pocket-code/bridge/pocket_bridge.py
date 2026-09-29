#!/usr/bin/env python3
"""CodeSpace Pocket native bridge. Python 3.10+, no third-party packages."""
import argparse, base64, errno, fcntl, hashlib, hmac, json, os, pathlib, pty, secrets, select, signal, struct, subprocess, tempfile, termios, threading, time, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs

MAX_FILE = 2 * 1024 * 1024
class Problem(Exception):
    def __init__(self, message, code=400): self.message, self.code = message, code

class Terminal:
    def __init__(self, root):
        self.lock = threading.Lock(); self.write_lock = threading.Lock(); self.buffer = bytearray(); self.base = 0; self.closed = False
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(root); os.environ.update(TERM='xterm-256color', COLORTERM='truecolor')
            os.execv('/bin/bash', ['bash', '-l'])
        self.resize(80, 24)
        threading.Thread(target=self.read, daemon=True).start()
    def read(self):
        try:
            while not self.closed:
                if not select.select([self.fd], [], [], 1)[0]: continue
                data = os.read(self.fd, 65536)
                if not data: break
                with self.lock:
                    self.buffer.extend(data)
                    extra = len(self.buffer) - 2 * 1024 * 1024
                    if extra > 0: del self.buffer[:extra]; self.base += extra
        except OSError: pass
        finally: self.closed = True
    def resize(self, cols, rows):
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack('HHHH', max(2,min(300,int(rows))), max(2,min(500,int(cols))),0,0))
    def output(self, offset):
        with self.lock:
            start = max(self.base, offset); data = bytes(self.buffer[start-self.base:])
            return dict(data=base64.b64encode(data).decode(), offset=self.base+len(self.buffer), truncated=offset<self.base, closed=self.closed)
    def close(self):
        self.closed = True
        try: os.killpg(self.pid, signal.SIGHUP)
        except ProcessLookupError: pass
        try: os.close(self.fd)
        except OSError: pass
        try: os.waitpid(self.pid, os.WNOHANG)
        except ChildProcessError: pass

class State:
    def __init__(self, root, token):
        self.root=pathlib.Path(root).resolve(); self.token=token; self.sessions={}; self.lock=threading.RLock()
    def path(self, relative):
        p=(self.root / relative).resolve()
        if not p.is_relative_to(self.root): raise Problem('路径不在工作区内',403)
        return p
    def git(self, args):
        p=subprocess.run(['git', '-C', str(self.root)]+args, capture_output=True, timeout=45, env={**os.environ,'GIT_TERMINAL_PROMPT':'0'})
        output=(p.stdout+p.stderr).decode('utf-8','replace')
        if p.returncode: raise Problem(output[:20000] or 'Git 操作失败',422)
        return output[:200000]
    def run(self, route, q, b, method):
        path=q.get('path',[''])[0]
        if route=='/health': return dict(version=2,root=str(self.root),name=self.root.name)
        if route=='/files' and method=='GET':
            p=self.path(path)
            if not p.is_dir(): raise Problem('目录不存在',404)
            entries=[]
            for x in sorted(p.iterdir(),key=lambda x:(not x.is_dir(),x.name.lower())):
                if x.name=='.git': continue
                try:
                    if not x.resolve().is_relative_to(self.root): continue
                    entries.append(dict(name=x.name,path=str(x.relative_to(self.root)),directory=x.is_dir()))
                except OSError: continue
            return dict(entries=entries[:2000])
        if route=='/file' and method=='GET':
            p=self.path(path)
            if not p.is_file(): raise Problem('文件不存在',404)
            if p.stat().st_size>MAX_FILE: raise Problem('编辑器支持 2 MB 以内的文本文件',413)
            data=p.read_bytes()
            if b'\0' in data: raise Problem('暂不支持二进制文件')
            try: content=data.decode('utf-8')
            except UnicodeError: raise Problem('仅支持 UTF-8 文本')
            return dict(content=content,revision=hashlib.sha256(data).hexdigest())
        if route=='/file' and method=='POST':
            with self.lock:
                p=self.path(b['path']); data=b['content'].encode('utf-8')
                if len(data)>MAX_FILE: raise Problem('文件超过 2 MB',413)
                if not p.is_file(): raise Problem('文件已被删除',409)
                if hashlib.sha256(p.read_bytes()).hexdigest()!=b.get('revision'): raise Problem('远端文件已改变。请先重新打开并合并修改，避免覆盖。',409)
                fd,temp=tempfile.mkstemp(dir=p.parent)
                try:
                    os.fchmod(fd,p.stat().st_mode & 0o777)
                    with os.fdopen(fd,'wb') as f: f.write(data); f.flush(); os.fsync(f.fileno())
                    os.replace(temp,p)
                finally:
                    if os.path.exists(temp): os.unlink(temp)
                return dict(revision=hashlib.sha256(data).hexdigest())
        if route=='/create' and method=='POST':
            p=self.path(b['path'])
            if p.exists(): raise Problem('文件或目录已存在',409)
            if b.get('directory'): p.mkdir()
            else:
                with p.open('x',encoding='utf8') as f: f.write('')
            return dict(ok=True)
        if route=='/git' and method=='GET':
            return dict(branch=self.git(['branch','--show-current']).strip(),status=self.git(['status','--short']),diff=self.git(['diff','--no-ext-diff','HEAD','--']),branches=self.git(['branch','--format=%(refname:short)']).splitlines())
        if route=='/git' and method=='POST':
            action=b['action']
            with self.lock:
                if action=='commit':
                    message=b.get('message','').strip()
                    if not message: raise Problem('请输入提交说明')
                    self.git(['add','-A']); result=self.git(['commit','-m',message])
                elif action=='push': result=self.git(['push'])
                elif action=='switch':
                    branch=b.get('branch','')
                    if branch not in self.git(['branch','--format=%(refname:short)']).splitlines(): raise Problem('请选择已有本地分支')
                    result=self.git(['switch','--',branch])
                else: raise Problem('未知 Git 操作')
            return dict(output=result)
        if route=='/terminal/new' and method=='POST':
            with self.lock:
                if len(self.sessions)>=8: raise Problem('终端会话数量已达上限，请关闭旧会话',429)
                sid=str(uuid.uuid4()); self.sessions[sid]=Terminal(str(self.root)); return dict(id=sid)
        if route.startswith('/terminal/'):
            sid=b.get('id') or q.get('id',[''])[0]; term=self.sessions.get(sid)
            if not term: raise Problem('终端会话不存在，请新建会话',404)
            if route=='/terminal/read': return term.output(int(q.get('offset',['0'])[0]))
            if route=='/terminal/write' and method=='POST':
                data=base64.b64decode(b['data'],validate=True)
                if len(data)>65536: raise Problem('输入过长',413)
                with term.write_lock:
                    while data: data=data[os.write(term.fd,data):]
            elif route=='/terminal/resize' and method=='POST': term.resize(b['cols'],b['rows'])
            elif route=='/terminal/close' and method=='POST':
                term.close(); self.sessions.pop(sid,None)
            else: raise Problem('未知终端操作',404)
            return dict(ok=True)
        raise Problem('接口不存在',404)

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_GET(self): self.handle_request('GET')
    def do_POST(self): self.handle_request('POST')
    def handle_request(self, method):
        try:
            supplied=self.headers.get('X-Pocket-Key','')
            if not hmac.compare_digest(supplied,self.server.state.token): raise Problem('连接密钥无效',401)
            if self.headers.get('Origin'): raise Problem('不允许浏览器跨域请求',403)
            n=int(self.headers.get('Content-Length','0'))
            if n<0 or n>MAX_FILE*3: raise Problem('请求过大',413)
            b=json.loads(self.rfile.read(n)) if n else {}
            u=urlsplit(self.path)
            if u.path=='/service/stop' and method=='POST':
                result={'ok':True}; code=200
                threading.Thread(target=self.server.shutdown,daemon=True).start()
            else:
                result=self.server.state.run(u.path,parse_qs(u.query),b,method); code=200
        except Problem as e: result={'error':e.message}; code=e.code
        except subprocess.TimeoutExpired: result={'error':'Git 操作超时，请在终端检查网络或认证'}; code=504
        except (OSError,ValueError,KeyError) as e: result={'error':str(e)}; code=400
        except Exception: result={'error':'服务错误，请查看 Codespace 状态'}; code=500
        data=json.dumps(result,ensure_ascii=False).encode(); self.send_response(code)
        self.send_header('Content-Type','application/json; charset=utf-8'); self.send_header('Cache-Control','no-store'); self.send_header('Content-Length',str(len(data))); self.end_headers()
        try: self.wfile.write(data)
        except (BrokenPipeError,ConnectionResetError): pass

def main():
    p=argparse.ArgumentParser(); p.add_argument('--root',default=os.getcwd()); p.add_argument('--port',type=int,default=8765); p.add_argument('--key-file'); p.add_argument('--quiet-auth',action='store_true'); a=p.parse_args()
    key=pathlib.Path(a.key_file).read_text().strip() if a.key_file else secrets.token_urlsafe(32)
    if len(key)<32: raise SystemExit('连接密钥长度不足')
    if not pathlib.Path(a.root).is_dir(): raise SystemExit('工作区目录不存在')
    server=ThreadingHTTPServer(('127.0.0.1',a.port),Handler); server.daemon_threads=True; server.state=State(a.root,key)
    print('\nCodeSpace Pocket 原生连接服务',flush=True)
    print('工作区:',server.state.root,flush=True)
    name=os.environ.get('CODESPACE_NAME'); domain=os.environ.get('GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN','app.github.dev')
    print('地址:',f'https://{name}-{a.port}.{domain}' if name else f'http://127.0.0.1:{a.port}',flush=True)
    if not a.quiet_auth: print('连接密钥:',key,flush=True)
    print('将 8765 端口转发并保持 Private。密钥只输入自己的客户端。Ctrl+C 停止服务。',flush=True)
    def terminate(signum, frame): raise KeyboardInterrupt
    signal.signal(signal.SIGTERM,terminate)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally:
        for t in list(server.state.sessions.values()): t.close()
        server.server_close()
if __name__=='__main__': main()
