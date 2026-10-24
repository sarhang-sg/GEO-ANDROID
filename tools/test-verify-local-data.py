#!/usr/bin/env python3
"""Exercise canonical pack identity and reject corrupt files before rewriting it."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('verify_local_data', Path(__file__).with_name('verify-local-data.py'))
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class PackIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        rows = []
        for name in ['groups/item.json', 'groups-manifest.json']:
            path = self.folder / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'{}')
            rows.append({'path': name, 'bytes': 2, 'sha256': hashlib.sha256(b'{}').hexdigest()})
        signature = ''.join(f'{r["path"]}\0{r["bytes"]}\0{r["sha256"]}\n' for r in rows)
        self.old_hash = hashlib.sha256(signature.encode()).hexdigest()
        manifest = {'versions': {'offlinePackVersion': '2027.13'}, 'files': rows,
                    'contentHash': self.old_hash, 'packId': '2027.13-' + self.old_hash[:16]}
        self.path = self.folder / 'manifest.json'
        self.path.write_text(json.dumps(manifest))

    def test_directory_traversal_identity_is_rejected(self):
        with self.assertRaisesRegex(SystemExit, 'canonical file inventory'):
            verifier.verify_pack(self.folder)

    def test_refresh_uses_complete_path_sort_order(self):
        manifest = verifier.verify_pack(self.folder, update_identity=True)
        self.assertEqual([r['path'] for r in manifest['files']],
                         ['groups-manifest.json', 'groups/item.json'])
        self.assertNotEqual(manifest['contentHash'], self.old_hash)
        self.assertEqual(manifest['packId'], '2027.13-' + manifest['contentHash'][:16])
        self.assertEqual(verifier.verify_pack(self.folder), manifest)

    def test_corruption_cannot_be_blessed_by_identity_refresh(self):
        before = self.path.read_bytes()
        (self.folder / 'groups/item.json').write_bytes(b'[]')
        with self.assertRaisesRegex(SystemExit, 'digest mismatch'):
            verifier.verify_pack(self.folder, update_identity=True)
        self.assertEqual(self.path.read_bytes(), before)

    def test_wrong_pack_id_is_rejected(self):
        manifest = verifier.verify_pack(self.folder, update_identity=True)
        manifest['packId'] = '2027.13-0000000000000000'
        self.path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(SystemExit, 'canonical file inventory'):
            verifier.verify_pack(self.folder)


if __name__ == '__main__':
    unittest.main()
