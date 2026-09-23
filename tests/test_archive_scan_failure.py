import sys, unittest, tempfile, plistlib, zipfile
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import input_source_migration as m
import hanjaime

class ScanFailureTests(unittest.TestCase):
 def scenario(self,status,output,accepted):
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp).resolve();app=root/'old app.app';(app/'Contents').mkdir(parents=True)
   (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':m.BUNDLE_ID,'CFBundleExecutable':'HanjaIME','InputMethodConnectionName':'HanjaIME_Connection'}))
   archive=root/'backup.zip';ls=root/'lsregister';ls.touch()
   def run(args,**kwargs):
    if str(args[0])=='/usr/bin/ditto':
     with zipfile.ZipFile(archive,'w') as z:z.write(app/'Contents/Info.plist',app.name+'/Contents/Info.plist')
     return 0
    return status,output.replace('{path}',str(app))
   with patch.object(m,'LSREGISTER',ls):
    if accepted:m.archive_bundle(app,archive,run,remove=True)
    else:
     with self.assertRaises(RuntimeError):m.archive_bundle(app,archive,run,remove=True)
   self.assertEqual(app.exists(),not accepted)
   with zipfile.ZipFile(archive) as z:self.assertIsNone(z.testzip())
 def test_observed_scan_failure(self):self.scenario(1,'failed to scan {path}: -10814\n from spotlight',True)
 def test_success(self):self.scenario(0,'',True)
 def test_permission_failure_retains_original(self):self.scenario(1,'permission denied',False)
 def test_other_path_retains_original(self):self.scenario(1,'failed to scan /another.app: -10814',False)
 def test_similar_code_retains_original(self):self.scenario(1,'failed to scan {path}: -108140',False)
 def test_mixed_error_retains_original(self):self.scenario(1,'failed to scan {path}: -10814\npermission denied',False)
 def test_capture_status(self):
  code,out=hanjaime.run([sys.executable,'-c','print("diagnostic");raise SystemExit(1)'],capture_status=True,check=False)
  self.assertEqual((code,out),(1,'diagnostic\n'))
