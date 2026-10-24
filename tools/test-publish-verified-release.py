#!/usr/bin/env python3
"""Exercise release publication failure boundaries without contacting GitHub."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SOURCE=Path(__file__).with_name('publish-verified-release.py')

class PublicationTests(unittest.TestCase):
    def exercise(self,case):
        calls=[]
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'tools').mkdir();(root/'release').mkdir();(root/'runner').mkdir()
            script=root/'tools/publish-verified-release.py';shutil.copyfile(SOURCE,script)
            (root/'SOURCE_MANIFEST.sha256').write_text('verified-source\n')
            certificate='A'*64
            (root/'ANDROID_APP_LINK_SHA256.txt').write_text(certificate)
            commit='b'*40
            metadata=dict(gitCommit=commit,versionName='10.4.4',versionCode=100404,packageId='com.navkurd.app',debuggable=False,
                          signingCertificateSha256=certificate,sourceManifestSha256=hashlib.sha256(b'verified-source\n').hexdigest(),workflowRunId='10',files={})
            for kind in ('apk','aab'):
                binary=root/'release'/('signed.'+kind);binary.write_bytes(b'CI-verified-fixture')
                metadata['files'][kind]=dict(name=binary.name,bytes=binary.stat().st_size)
            (root/'release/RELEASE-METADATA.json').write_text(json.dumps(metadata))
            spec=importlib.util.spec_from_file_location('publisher',script);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
            def fake_gh(*args,**kwargs):
                calls.append(args)
                if args[0]=='api':
                    if case=='resume-draft':
                        receipt={k:metadata[k] for k in ('packageId','versionName','versionCode','gitCommit','workflowRunId','sourceManifestSha256','signingCertificateSha256')}
                        receipt['files']={kind:dict(name=f'NAV-KURD-10.4.4.{kind}',bytes=len(b'CI-verified-fixture'),sha256=hashlib.sha256(b'CI-verified-fixture').hexdigest()) for kind in ('apk','aab')}
                        receipt_url='https://api.github.com/repos/owner/repo/releases/assets/100'
                        if '--slurp' in args:
                            return SimpleNamespace(returncode=0,stdout=json.dumps([[{'id':99,'tag_name':'v10.4.4-candidate-'+commit[:12]}]]),stderr='')
                        if args[1]=='repos/owner/repo/releases/99':
                            assets=[dict(name=f['name'],size=f['bytes'],digest='sha256:'+f['sha256'],state='uploaded') for f in receipt['files'].values()]
                            assets.append(dict(name='DOWNLOAD-RECEIPT.json',url=receipt_url))
                            return SimpleNamespace(returncode=0,stdout=json.dumps({'assets':assets}),stderr='')
                        if args[1]==receipt_url:return SimpleNamespace(returncode=0,stdout=json.dumps(receipt),stderr='')
                        if '/releases/tags/' in args[1]:raise AssertionError('Private draft must be read by ID, not by-tag endpoint')
                    if case=='wrong-tag':return SimpleNamespace(returncode=0,stdout=json.dumps({'object':{'type':'commit','sha':'c'*40}}),stderr='')
                    return SimpleNamespace(returncode=1,stdout='',stderr='HTTP 404')
                if args[:2]==('release','view'):
                    if case=='resume-draft':return SimpleNamespace(returncode=0,stdout=json.dumps({'isDraft':True,'targetCommitish':commit}),stderr='')
                    if case=='other-draft':return SimpleNamespace(returncode=0,stdout=json.dumps({'isDraft':True,'targetCommitish':'c'*40}),stderr='')
                    return SimpleNamespace(returncode=1,stdout='',stderr='not found')
                if args[:2]==('release','upload') and case=='upload-failed':raise SystemExit('simulated interrupted upload')
                return SimpleNamespace(returncode=0,stdout='',stderr='')
            environment=dict(GITHUB_REF='refs/heads/main',NAV_KURD_VERSION='10.4.4',NAV_KURD_VERSION_CODE='100404',GITHUB_SHA=commit,GITHUB_REPOSITORY='owner/repo',RUNNER_TEMP=str(root/'runner'))
            previous=Path.cwd()
            try:
                with patch.dict(os.environ,environment),patch.object(module,'gh',side_effect=fake_gh):
                    if case in ('success','resume-draft'):module.main()
                    else:
                        with self.assertRaises(SystemExit):module.main()
            finally:os.chdir(previous)
            mutating=[c[:2] for c in calls if c[:2] in [('release','create'),('release','upload')]]
            if case=='success':
                self.assertEqual(mutating,[('release','create'),('release','upload')])
                create=next(c for c in calls if c[:2]==('release','create'))
                self.assertEqual(create[2],'v10.4.4-candidate-'+commit[:12])
                self.assertIn('--draft',create)
                self.assertFalse(any(c[:3]==('release','edit','v10.4.4') for c in calls))
                receipt=json.loads((root/'runner/nav-kurd-publish-10.4.4/DOWNLOAD-RECEIPT.json').read_text())
                self.assertEqual(receipt['gitCommit'],commit)
                self.assertEqual(receipt['files']['apk']['sha256'],hashlib.sha256(b'CI-verified-fixture').hexdigest())
            elif case=='upload-failed':self.assertNotIn(('release','edit'),mutating)
            else:self.assertEqual(mutating,[])
    def test_order_and_receipt(self):self.exercise('success')
    def test_partial_upload_remains_draft(self):self.exercise('upload-failed')
    def test_other_source_draft_is_preserved(self):self.exercise('other-draft')
    def test_existing_version_tag_is_not_moved(self):self.exercise('wrong-tag')
    def test_complete_private_draft_resumes_by_id_without_duplicate_upload(self):self.exercise('resume-draft')

if __name__=='__main__':unittest.main()
