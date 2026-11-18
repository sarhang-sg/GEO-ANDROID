#!/usr/bin/env python3
"""Retire superseded application downloads after the public website selects this release."""
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen


def read_json(url):
    with urlopen(Request(url, headers={'User-Agent': 'NAV-KURD-release'}), timeout=20) as response:
        return json.load(response)


def github(path, method='GET', missing_ok=False):
    result = subprocess.run(['gh', 'api', path, '--method', method],
                            text=True, capture_output=True, check=False)
    if result.returncode:
        if missing_ok and 'HTTP 404' in result.stderr:
            return None
        raise RuntimeError(result.stderr.strip() or f'GitHub {method} failed')
    return json.loads(result.stdout) if result.stdout.strip() else None


def publication_state(repo, version):
    """Reuse an immutable signed release for publication-only maintenance."""
    stable = 'v' + version
    release = github(f'repos/{repo}/releases/tags/{quote(stable, safe="")}', missing_ok=True)
    source = os.environ['GITHUB_SHA']
    if release is not None:
        if release['draft'] or release['prerelease'] or not release.get('published_at'):
            raise RuntimeError('The version tag does not identify a published stable release')
        reference = github(f'repos/{repo}/git/ref/tags/{quote(stable, safe="")}')['object']
        for _ in range(5):
            if reference['type'] == 'commit':
                break
            if reference['type'] != 'tag':
                raise RuntimeError('The release tag does not resolve to a commit')
            reference = github(f'repos/{repo}/git/tags/{reference["sha"]}')['object']
        if reference['type'] != 'commit':
            raise RuntimeError('The release tag chain is too long')
        source = reference['sha']
        receipt = read_json(f'https://github.com/{repo}/releases/download/{stable}/DOWNLOAD-RECEIPT.json')
        certificate = Path('ANDROID_APP_LINK_SHA256.txt').read_text().replace(':', '').strip().upper()
        if (receipt['gitCommit'] != source or receipt['versionName'] != version
                or receipt['versionCode'] != int(os.environ['NAV_KURD_VERSION_CODE'])
                or receipt['packageId'] != 'com.navkurd.app'
                or receipt['signingCertificateSha256'] != certificate):
            raise RuntimeError('The published release does not match its tag and established signing identity')
        subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', source], check=True)
        changed = subprocess.check_output(['git', 'diff', '--name-only', source, 'HEAD'], text=True).splitlines()
        maintenance = {'SOURCE_MANIFEST.sha256', 'README.md', 'SECURITY.md',
                       'tools/prune-published-versions.py', '.github/workflows/android-release.yml'}
        unexpected = [path for path in changed if path not in maintenance]
        if unexpected:
            raise RuntimeError('A published app version is immutable. Bump the version before changing: ' + ', '.join(unexpected))
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        output.write(f'published={str(release is not None).lower()}\nrelease_commit={source}\n')
    print('Verified existing signed release' if release is not None else 'New signed build required', version)


def main():
    version = os.environ['NAV_KURD_VERSION']
    commit = os.environ.get('NAV_KURD_RELEASE_COMMIT') or os.environ['GITHUB_SHA']
    repo = os.environ['GITHUB_REPOSITORY']
    if repo != 'sarhang-sg/GEO-ANDROID':
        raise SystemExit('Unexpected release repository')
    if sys.argv[1:] == ['--state']:
        publication_state(repo, version)
        return
    if sys.argv[1:]:
        raise SystemExit('Unknown publication option')
    stable = 'v' + version
    receipt = read_json(f'https://github.com/{repo}/releases/download/{stable}/DOWNLOAD-RECEIPT.json')
    if receipt['gitCommit'] != commit or receipt['versionName'] != version:
        raise SystemExit('Published source differs from the release being retired')
    deadline = time.monotonic() + 900
    while True:
        try:
            public = read_json('https://geo-map-kappa.vercel.app/releases/latest.json')
            if (public.get('version') == version
                    and public.get('artifact', {}).get('gitCommit') == commit
                    and public.get('apkSha256') == receipt['files']['apk']['sha256']):
                break
        except (OSError, ValueError):
            pass
        if time.monotonic() >= deadline:
            raise SystemExit('Web publication has not selected this signed release yet')
        time.sleep(20)
    releases = json.loads(subprocess.check_output([
        'gh', 'api', '--paginate', '--slurp', f'repos/{repo}/releases?per_page=100'
    ]))
    current = tuple(map(int, version.split('.')))
    for page in releases:
        for release in page:
            tag = release['tag_name']
            match = re.fullmatch(r'v?(\d+)\.(\d+)\.(\d+)(?:-(?:candidate|retired)-.*)?', tag)
            if tag == stable or not match:
                continue
            if tuple(map(int, match.groups())) > current:
                continue
            subprocess.run(['gh', 'release', 'delete', tag, '--repo', repo, '--yes'], check=True)
            # Draft candidates have no Git tag. Retiring their release must not
            # stop cleanup of older published APKs when that tag is absent.
            encoded = quote(tag, safe='')
            if github(f'repos/{repo}/git/ref/tags/{encoded}', missing_ok=True) is not None:
                github(f'repos/{repo}/git/refs/tags/{encoded}', method='DELETE', missing_ok=True)
            print('Retired application release', tag)
    print('Current signed release and offline road graph remain available')


if __name__ == '__main__':
    main()
