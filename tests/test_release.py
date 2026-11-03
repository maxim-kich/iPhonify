import importlib.util,json,pathlib,tempfile,unittest
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('release',pathlib.Path(__file__).parents[1]/'scripts/release.py')
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
class ReleaseTests(unittest.TestCase):
 def test_resume_does_not_resubmit(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);(p/'dmg-submission.json').write_text('{"id":"saved-id"}')
   with patch.object(r,'capture',return_value='{"status":"Accepted"}') as capture,patch.object(r,'run') as run,patch.object(r.subprocess,'run'):
    r.notarize_file(p,p/'test.dmg','profile','dmg')
    self.assertFalse(any('submit' in c.args for c in capture.call_args_list))
    self.assertTrue(any('staple' in c.args for c in run.call_args_list))
 def test_pending_does_not_staple(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);(p/'dmg-submission.json').write_text('{"id":"saved-id"}')
   with patch.object(r,'capture',return_value='{"status":"In Progress"}'),patch.object(r,'run') as run,patch.object(r.subprocess,'run'):
    with self.assertRaises(SystemExit):r.notarize_file(p,p/'test.dmg','profile','dmg')
    run.assert_not_called()
 def test_dirty_draft_refused(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);(p/'manifest.json').write_text(json.dumps({'version':'0.1.0','stage':'notarized','dirty':True}))
   with patch.object(r,'run') as run:
    with self.assertRaises(SystemExit):r.draft(p,True)
    run.assert_not_called()
 def test_modified_source_refused_before_network(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);(p/'source.tar.gz').write_text('changed')
   (p/'manifest.json').write_text(json.dumps({'source':'source.tar.gz','source_sha256':'wrong'}))
   with patch.object(r,'run') as run:
    with self.assertRaises(SystemExit):r.notarize(p,'profile')
    run.assert_not_called()
 def test_bind_keeps_approved_assets_and_only_updates_provenance(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);(p/'source.tar.gz').write_text('source');(p/'app.zip').write_text('approved')
   files={'README.md':'reviewed-source-hash'}
   manifest={'source':'source.tar.gz','source_sha256':r.digest(p/'source.tar.gz'),'source_files':files,'asset_sha256':{'app.zip':r.digest(p/'app.zip')},'dirty':True,'commit':'baseline','stage':'notarized'}
   (p/'manifest.json').write_text(json.dumps(manifest))
   def capture(*args):
    if args==('git','status','--porcelain'):return ''
    if args==('git','ls-files','-z'):return 'README.md\0'
    if args==('git','rev-parse','HEAD'):return 'approved-initial-commit'
    raise AssertionError(args)
   with patch.object(r,'source_manifest',return_value=files),patch.object(r,'capture',side_effect=capture),patch.object(r,'run') as run:
    r.bind(p);run.assert_not_called()
   result=json.loads((p/'manifest.json').read_text());self.assertFalse(result['dirty']);self.assertEqual(result['commit'],'approved-initial-commit')
   self.assertEqual((p/'app.zip').read_text(),'approved')
 def test_bind_rejects_modified_review_asset(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);(p/'source.tar.gz').write_text('source');(p/'app.zip').write_text('changed')
   files={'README.md':'reviewed'}
   (p/'manifest.json').write_text(json.dumps({'source':'source.tar.gz','source_sha256':r.digest(p/'source.tar.gz'),'source_files':files,'asset_sha256':{'app.zip':'original-hash'}}))
   with patch.object(r,'source_manifest',return_value=files),patch.object(r,'capture',side_effect=['','README.md\0']),patch.object(r,'run') as run:
    with self.assertRaises(SystemExit):r.bind(p)
    run.assert_not_called()
 def test_submitted_artifact_cannot_change(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);(p/'test.dmg').write_text('changed')
   (p/'dmg-submission.json').write_text(json.dumps({'id':'existing-id','artifact_sha256':'original-hash'}))
   with patch.object(r,'capture') as capture,patch.object(r,'run') as run:
    with self.assertRaises(SystemExit):r.notarize_file(p,p/'test.dmg','profile','dmg')
    capture.assert_not_called();run.assert_not_called()
if __name__=='__main__':unittest.main()
