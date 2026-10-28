#!/usr/bin/env python3
"""Exercise the real manifest CLI without editing a release checkout."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest


class ManifestTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'tools').mkdir()
        self.tool = self.root / 'tools/update-source-manifest.py'
        shutil.copyfile(Path(__file__).with_name('update-source-manifest.py'), self.tool)
        (self.root / 'a.txt').write_text('original')
        (self.root / 'missing.txt').write_text('present')
        self.assertEqual(self.run_tool().returncode, 0)

    def run_tool(self, *args):
        return subprocess.run([sys.executable, str(self.tool), *args], text=True, capture_output=True)

    def test_roundtrip_and_precise_diagnostics(self):
        self.assertEqual(self.run_tool('--check').returncode, 0)
        (self.root / 'a.txt').write_text('modified')
        (self.root / 'missing.txt').rename(self.root / 'added.txt')
        result = self.run_tool('--check')
        self.assertNotEqual(result.returncode, 0)
        for message in ('Changed (1): a.txt', 'Missing (1): missing.txt', 'Unexpected (1): added.txt'):
            self.assertIn(message, result.stdout)

    def test_partial_transfers_never_enter_or_rewrite_manifest(self):
        manifest = self.root / 'SOURCE_MANIFEST.sha256'
        original = manifest.read_bytes()
        for name in ('.catalog.sqlite.Yk9XNN', '.catalog.sqlite.Yk9XNN.jxvhg6'):
            path = self.root / name
            path.write_text('partial catalog')
            for args in ((), ('--check',)):
                result = self.run_tool(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(name, result.stderr)
                self.assertEqual(manifest.read_bytes(), original)
            path.rename(self.root / (name + '.tmp'))

    def test_lfs_pointer_never_becomes_release_source(self):
        manifest = self.root / 'SOURCE_MANIFEST.sha256'
        original = manifest.read_bytes()
        (self.root / 'data.bin').write_text(
            'version https://git-lfs.github.com/spec/v1\n'
            'oid sha256:' + 'a' * 64 + '\nsize 422789120\n')
        for args in ((), ('--check',)):
            result = self.run_tool(*args)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Unmaterialized Git LFS pointer: data.bin', result.stderr)
            self.assertEqual(manifest.read_bytes(), original)

    def test_catalog_requires_approved_size_and_digest(self):
        core = self.root / 'android/app/src/main/assets/nav_kurd_core'
        core.mkdir(parents=True)
        catalog = core / 'catalog.sqlite'
        data = b'SQLite format 3\0' + bytes(range(256))
        catalog.write_bytes(data)
        (core / 'manifest.json').write_text(json.dumps({'files': [{
            'path': 'catalog.sqlite', 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest()
        }]}))
        self.assertEqual(self.run_tool().returncode, 0)
        self.assertEqual(self.run_tool('--check').returncode, 0)
        manifest = self.root / 'SOURCE_MANIFEST.sha256'
        original = manifest.read_bytes()
        for content in (data[:-1], b'X' + data[1:], None):
            if content is None:
                catalog.unlink()
            else:
                catalog.write_bytes(content)
            for args in ((), ('--check',)):
                with self.subTest(content=content is None, args=args):
                    result = self.run_tool(*args)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('Catalog integrity mismatch', result.stderr)
                    self.assertEqual(manifest.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
