#!/usr/bin/env python3
"""Replace the bundled UI with a verified build from the matching web source."""
import argparse
import hashlib
import json
from pathlib import Path
import os
import subprocess
import shutil
import tempfile


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--web',type=Path,required=True)
    parser.add_argument('--dist',type=Path,help='Previously built Android presentation directory')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    web=args.web.resolve()
    release=json.loads((web/'release.config.json').read_text())
    application=json.loads((root/'assets/application-release.json').read_text())
    if application.get('presentationVersion') != release['appVersion']:
        raise SystemExit('The web build differs from the presentation version declared by Android.')
    build = tempfile.TemporaryDirectory(prefix='nav-kurd-android-dist-')
    dist = args.dist.resolve() if args.dist else Path(build.name)
    if not args.dist:
        subprocess.run([str(web/'node_modules/.bin/vite'),'build','--outDir',str(dist)],
                       cwd=web,env={**os.environ,'NAV_KURD_ANDROID_PRESENTATION':'1'},check=True)
    source=[dist/'index.html',dist/'weather-cities.html',dist/'manifest.webmanifest',
            *sorted((dist/'assets').glob('*.js')), *sorted((dist/'assets').glob('*.css')),
            *sorted((dist/'assets/weather').glob('*.svg')), *sorted((dist/'fonts').glob('*.ttf')),
            *sorted((dist/'fonts').glob('*.woff2')), *sorted((dist/'legal').glob('*'))]
    if not all(p.is_file() for p in source[:3]) or not any(
        '__NAV_KURD_PUBLIC_CONFIG__' in p.read_text() for p in source if p.suffix=='.js'
    ) or (dist/'client-config.json').exists():
        raise SystemExit('Build the native presentation with NAV_KURD_ANDROID_PRESENTATION=1.')
    destination=root/'assets/r16'
    # Share exact provider descriptions with the native widget/notifications.
    shutil.copyfile(web/'contracts/weather-descriptions.json', root/'android/app/src/main/assets/nav_kurd_weather_descriptions.json')
    with tempfile.TemporaryDirectory(prefix='nav-kurd-ui-') as temporary:
        staging=Path(temporary)/'r16';staging.mkdir()
        rows=[]
        for path in sorted(source,key=lambda p:p.relative_to(dist).as_posix()):
            if not path.is_file():continue
            relative=path.relative_to(dist).as_posix()
            target=staging/relative;target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(path,target)
            rows.append(dict(path=relative,bytes=target.stat().st_size,sha256=sha(target)))
        manifest=dict(schema=1,appVersion=release['appVersion'],releaseId=release['releaseId'],
            configurationSource='/client-config.json',
            contentHash=hashlib.sha256(''.join(f'{r["path"]}\0{r["bytes"]}\0{r["sha256"]}\n' for r in rows).encode()).hexdigest(),files=rows)
        (staging/'manifest.json').write_text(json.dumps(manifest,separators=(',',':'))+'\n')
        # This directory is a generated, manifest-owned presentation only.
        shutil.rmtree(destination)
        shutil.copytree(staging,destination)
    print(f'Synced {len(rows)} UI files for {release["appVersion"]}; native core data unchanged.')


if __name__=='__main__':main()
