#!/usr/bin/env python3
import json,os,pathlib,socket,subprocess,tempfile,unittest,urllib.request
SOURCE=pathlib.Path(__file__).resolve().parents[2]
class InstallerTest(unittest.TestCase):
 def test_autostart(self):
  with tempfile.TemporaryDirectory(prefix='pocket autostart ') as t:
   base=pathlib.Path(t);home=base/'service';bindir=base/'bin'
   with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
   env={**os.environ,'POCKET_CODE_HOME':str(home),'POCKET_CODE_BIN_DIR':str(bindir),'POCKET_BRIDGE_PORT':str(port)}
   env.pop('CODESPACE_NAME',None)
   cli=[str(bindir/'pocket-code')]
   def launch():
    result=subprocess.run(['bash',str(SOURCE/'.devcontainer/start-bridge.sh')],cwd=t,env=env,capture_output=True,text=True,timeout=20)
    self.assertEqual(result.returncode,0,result.stderr)
    return result.stdout
   try:
    output=launch();key=(home/'connection.key').read_text();pid=json.loads((home/'process.json').read_text())['pid']
    self.assertNotIn(key.strip(),output)
    self.assertNotIn(key.strip(),launch())
    self.assertEqual(pid,json.loads((home/'process.json').read_text())['pid'])
    subprocess.run(cli+['stop'],env=env,check=True,capture_output=True,timeout=20)
    launch()
    self.assertEqual(key,(home/'connection.key').read_text())
    self.assertEqual(json.loads((home/'config.json').read_text())['root'],str(SOURCE))
   finally:
    if (bindir/'pocket-code').exists():subprocess.run(cli+['stop'],env=env,capture_output=True,timeout=20)
 def test_lifecycle(self):
  with tempfile.TemporaryDirectory(prefix='pocket test ') as t:
   base=pathlib.Path(t);workspace=base/'project with spaces';workspace.mkdir();other=base/'other';other.mkdir()
   home=base/'service';bindir=base/'bin';env={**os.environ,'POCKET_CODE_HOME':str(home),'POCKET_CODE_BIN_DIR':str(bindir)}
   env.pop('CODESPACE_NAME',None)
   with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
   install=['bash',str(SOURCE/'install.sh'),'--source-dir',str(SOURCE),'--root',str(workspace),'--port',str(port)]
   def run(args,ok=True):
    p=subprocess.run(args,env=env,capture_output=True,text=True,timeout=20)
    if ok:self.assertEqual(p.returncode,0,p.stderr)
    else:self.assertNotEqual(p.returncode,0)
    return p
   cli=[str(bindir/'pocket-code')]
   try:
    run(install);key=(home/'connection.key').read_text();pid=json.loads((home/'process.json').read_text())['pid']
    self.assertEqual((home/'connection.key').stat().st_mode&0o777,0o600)
    self.assertNotIn(key.strip(),(home/'service.log').read_text())
    run(install);self.assertEqual(key,(home/'connection.key').read_text());self.assertEqual(pid,json.loads((home/'process.json').read_text())['pid'])
    run(cli+['configure','--root',str(other),'--port',str(port)],ok=False)
    run(cli+['restart']);self.assertEqual(key,(home/'connection.key').read_text());self.assertNotEqual(pid,json.loads((home/'process.json').read_text())['pid'])
    req=urllib.request.Request(f'http://127.0.0.1:{port}/health',headers={'X-Pocket-Key':key.strip()})
    with urllib.request.urlopen(req) as response:self.assertEqual(json.load(response)['root'],str(workspace))
    run(cli+['stop']);run(cli+['status'],ok=False);run(cli+['stop'])
    run(cli+['start']);run(cli+['status'])
   finally:
    if (bindir/'pocket-code').exists():run(cli+['stop'])
if __name__=='__main__':unittest.main(verbosity=2)
