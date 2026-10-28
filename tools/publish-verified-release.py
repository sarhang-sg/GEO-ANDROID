#!/usr/bin/env python3
"""Stage a verified draft for publication by the owner release coordinator."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def gh(*args, check=True):
    result = subprocess.run(['gh', *args], check=False, text=True, capture_output=True)
    if check and result.returncode:
        raise SystemExit(f'GitHub release operation failed ({args[0]}): {result.stderr.strip()}')
    return result


def main():
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    if os.environ.get('GITHUB_REF') != 'refs/heads/main':
        raise SystemExit('Publishing requires the protected main release source.')
    metadata = json.loads(Path('release/RELEASE-METADATA.json').read_text())
    version = os.environ['NAV_KURD_VERSION']
    commit = os.environ['GITHUB_SHA']
    certificate = Path('ANDROID_APP_LINK_SHA256.txt').read_text().replace(':', '').strip().upper()
    source_hash = hashlib.sha256(Path('SOURCE_MANIFEST.sha256').read_bytes()).hexdigest()
    if (metadata['gitCommit'] != commit or metadata['versionName'] != version
            or metadata['versionCode'] != int(os.environ['NAV_KURD_VERSION_CODE'])
            or metadata['packageId'] != 'com.navkurd.app'
            or metadata['debuggable'] is not False
            or metadata['signingCertificateSha256'] != certificate
            or metadata['sourceManifestSha256'] != source_hash):
        raise SystemExit('The signed release identity does not match this source.')
    repository = os.environ['GITHUB_REPOSITORY']
    # A rebuilt app may intentionally retain its public app version. Stage by
    # exact source so the currently downloadable signed release remains intact.
    # Only the owner coordinator promotes this verified draft to v<version>.
    tag = f'v{version}-candidate-{commit[:12]}'
    reference = gh('api', f'repos/{repository}/git/ref/tags/{tag}', check=False)
    if reference.returncode == 0:
        target = json.loads(reference.stdout)['object']
        for _ in range(6):
            if target['type'] != 'tag':
                break
            target = json.loads(gh('api', target['url']).stdout)['object']
        if target.get('type') != 'commit' or target.get('sha') != commit:
            raise SystemExit('Existing version tag points at a different source; it will not be moved.')
    elif '404' not in reference.stderr:
        raise SystemExit('Could not verify whether the release tag already exists.')
    staging = Path(os.environ['RUNNER_TEMP']) / ('nav-kurd-publish-' + version)
    staging.mkdir(exist_ok=True)
    receipt = {key: metadata[key] for key in (
        'packageId', 'versionName', 'versionCode', 'gitCommit', 'workflowRunId',
        'sourceManifestSha256', 'signingCertificateSha256')}
    receipt['files'] = {}
    for kind in ('apk', 'aab'):
        original = Path('release') / metadata['files'][kind]['name']
        name = f'NAV-KURD-{version}.{kind}'
        with original.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        if original.stat().st_size != metadata['files'][kind]['bytes']:
            raise SystemExit('Verified binary size changed before publishing.')
        receipt['files'][kind] = {'name': name, 'bytes': original.stat().st_size, 'sha256': digest}
        shutil.copyfile(original, staging / name)
    receipt_path = staging / 'DOWNLOAD-RECEIPT.json'
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
    existing = gh('release', 'view', tag, '--repo', repository, '--json', 'isDraft,targetCommitish', check=False)
    if existing.returncode == 0:
        identity = json.loads(existing.stdout)
        if identity['isDraft'] and identity['targetCommitish'] != commit:
            raise SystemExit('Existing draft targets a different source; it will not be replaced.')
        # The by-tag REST endpoint can return 404 for a private draft. Resolve
        # its stable ID from the authenticated collection, including all pages.
        pages = json.loads(gh('api', '--paginate', '--slurp',
                             f'repos/{repository}/releases?per_page=100').stdout)
        matches = [item for page in pages for item in page if item.get('tag_name') == tag]
        if len(matches) != 1 or not isinstance(matches[0].get('id'), int):
            raise SystemExit('The existing candidate draft could not be uniquely identified.')
        prior = json.loads(gh('api', f'repos/{repository}/releases/{matches[0]["id"]}').stdout)
        prior_assets = prior['assets']
        complete = all(any(a['name'] == n for a in prior_assets) for n in
                       ('DOWNLOAD-RECEIPT.json', f'NAV-KURD-{version}.apk', f'NAV-KURD-{version}.aab'))
        if not identity['isDraft'] or complete:
            assets = prior_assets
            descriptor = next((a for a in assets if a['name'] == 'DOWNLOAD-RECEIPT.json'), None)
            if descriptor is None:
                raise SystemExit('Existing public release has no verified receipt; it will not be replaced.')
            old = json.loads(gh('api', descriptor['url'], '-H', 'Accept: application/octet-stream').stdout)
            if (old.get('gitCommit') != commit or old.get('sourceManifestSha256') != source_hash
                    or old.get('versionName') != version or old.get('versionCode') != int(os.environ['NAV_KURD_VERSION_CODE'])
                    or old.get('packageId') != 'com.navkurd.app' or old.get('signingCertificateSha256') != certificate):
                raise SystemExit('This version already belongs to a different source; use a new version.')
            for kind in ('apk', 'aab'):
                expected = old.get('files', {}).get(kind, {})
                asset = next((a for a in assets if a['name'] == expected.get('name')), None)
                if (asset is None or asset.get('size') != expected.get('bytes')
                        or expected.get('name') != f'NAV-KURD-{version}.{kind}'
                        or len(expected.get('sha256', '')) != 64
                        or asset.get('digest') != 'sha256:' + expected['sha256'] or asset.get('state') != 'uploaded'):
                    raise SystemExit('Existing release assets do not match their receipt; no overwrite attempted.')
            print('Same complete verified release already exists; binaries retained without publication or overwrite.')
            return
    else:
        gh('release', 'create', tag, '--repo', repository, '--target', commit,
           '--draft', '--title', f'NAV KURD {version}', '--notes-file', 'docs/RELEASE.md')
    # Retry only incomplete drafts of the same source. Publication is a later owner step.
    gh('release', 'upload', tag, '--repo', repository, '--clobber',
       *[str(staging / f'NAV-KURD-{version}.{kind}') for kind in ('apk', 'aab')], str(receipt_path))
    print(f'Staged verified {tag}; the owner coordinator verifies and publishes this exact candidate.')


if __name__ == '__main__':
    main()
