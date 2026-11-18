#!/usr/bin/env python3
"""Retire superseded application downloads after the public website selects this release."""
import json
import os
import re
import subprocess
import time
from urllib.request import Request, urlopen


def read_json(url):
    with urlopen(Request(url, headers={'User-Agent': 'NAV-KURD-release'}), timeout=20) as response:
        return json.load(response)


def main():
    version = os.environ['NAV_KURD_VERSION']
    commit = os.environ['GITHUB_SHA']
    repo = os.environ['GITHUB_REPOSITORY']
    if repo != 'sarhang-sg/GEO-ANDROID':
        raise SystemExit('Unexpected release repository')
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
            subprocess.run(['gh', 'release', 'delete', tag, '--repo', repo,
                            '--cleanup-tag', '--yes'], check=True)
            print('Retired application release', tag)
    print('Current signed release and offline road graph remain available')


if __name__ == '__main__':
    main()
