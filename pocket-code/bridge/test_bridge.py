import importlib.util, pathlib, tempfile, unittest, subprocess, time, threading, urllib.request, urllib.error, json, base64
spec=importlib.util.spec_from_file_location('bridge',pathlib.Path(__file__).with_name('pocket_bridge.py')); b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
class BridgeTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.tmp.name);(self.root/'a.py').write_text('print(1)\n');self.state=b.State(self.root,'test-key');self.server=b.ThreadingHTTPServer(('127.0.0.1',0),b.Handler);self.server.state=self.state;threading.Thread(target=self.server.serve_forever,daemon=True).start()
 def tearDown(self):
  for t in list(self.state.sessions.values()):t.close()
  self.server.shutdown();self.server.server_close();self.tmp.cleanup()
 def call(self,path,body=None,key='test-key'):
  r=urllib.request.Request('http://127.0.0.1:%s%s'%(self.server.server_port,path),data=None if body is None else json.dumps(body).encode(),headers={'X-Pocket-Key':key})
  return json.load(urllib.request.urlopen(r,timeout=5))
 def test_auth_and_traversal(self):
  for path,key,code in [('/health','wrong',401),('/file?path=../../etc/passwd','test-key',403)]:
   with self.assertRaises(urllib.error.HTTPError) as e:self.call(path,key=key)
   self.assertEqual(e.exception.code,code)
  (self.root/'escape').symlink_to('/etc/passwd')
  with self.assertRaises(urllib.error.HTTPError) as e:self.call('/file?path=escape')
  self.assertEqual(e.exception.code,403)
 def test_edit_conflict_and_create(self):
  r=self.call('/file?path=a.py');self.call('/file',{'path':'a.py','revision':r['revision'],'content':'你好\n'})
  self.assertEqual((self.root/'a.py').read_text(),'你好\n')
  with self.assertRaises(urllib.error.HTTPError) as e:self.call('/file',{'path':'a.py','revision':r['revision'],'content':'stale'})
  self.assertEqual(e.exception.code,409)
  self.call('/create',{'path':'new.txt','directory':False});self.assertTrue((self.root/'new.txt').exists())
 def test_pty(self):
  sid=self.call('/terminal/new',{})['id'];self.call('/terminal/resize',{'id':sid,'cols':100,'rows':30})
  command="printf 'POCKET_%s\\n' READY\n"
  self.call('/terminal/write',{'id':sid,'data':base64.b64encode(command.encode()).decode()})
  result=b''
  for _ in range(30):
   result=base64.b64decode(self.call('/terminal/read?id='+sid+'&offset=0')['data'])
   if b'POCKET_READY' in result:break
   time.sleep(.1)
  self.assertIn(b'POCKET_READY',result);self.call('/terminal/close',{'id':sid})
 def test_git(self):
  for args in [['init'],['config','user.email','test@example.invalid'],['config','user.name','Test']]:subprocess.run(['git','-C',str(self.root)]+args,check=True,capture_output=True)
  self.call('/git',{'action':'commit','message':'Initial'})
  (self.root/'a.py').write_text('changed\n')
  result=self.call('/git');self.assertIn('a.py',result['status']);self.assertIn('+changed',result['diff'])
  subprocess.run(['git','-C',str(self.root),'branch','other'],check=True)
  self.call('/git',{'action':'switch','branch':'other'});self.assertEqual(self.call('/git')['branch'],'other')
if __name__=='__main__':unittest.main(verbosity=2)
