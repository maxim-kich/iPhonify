import base64, pathlib, plistlib, subprocess, sys, tempfile, unittest
SCRIPT=pathlib.Path(__file__).parents[1]/'scripts/configure-updater.py'
class UpdaterConfigTests(unittest.TestCase):
 def configure(self,key):
  with tempfile.TemporaryDirectory() as directory:
   folder=pathlib.Path(directory);info=folder/'Info.plist';public=folder/'key.txt'
   info.write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.maximkich.iphonify'}));public.write_text(key)
   result=subprocess.run([sys.executable,str(SCRIPT),str(info),str(public)],capture_output=True)
   return result,plistlib.loads(info.read_bytes())
 def test_development_has_no_signing_authority(self):
  result,info=self.configure('');self.assertEqual(result.returncode,0)
  self.assertNotIn('SUPublicEDKey',info)
  self.assertFalse(info['SUEnableAutomaticChecks']);self.assertFalse(info['SUAutomaticallyUpdate'])
  self.assertTrue(info['SURequireSignedFeed']);self.assertTrue(info['SUVerifyUpdateBeforeExtraction'])
  self.assertEqual(info['SUSignedFeedFailureExpirationInterval'],0)
 def test_valid_public_key_and_project_feed(self):
  key=base64.b64encode(bytes(range(32))).decode();result,info=self.configure(key)
  self.assertEqual(result.returncode,0);self.assertEqual(info['SUPublicEDKey'],key)
  self.assertEqual(info['SUFeedURL'],'https://github.com/maxim-kich/iPhonify/releases/latest/download/appcast.xml')
 def test_invalid_key_rejected(self):
  result,_=self.configure('invalid');self.assertNotEqual(result.returncode,0)
if __name__=='__main__':unittest.main()
