#!/usr/bin/env python3
"""Replace the bundled UI with a verified build from the matching web source."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--web',type=Path,required=True)
    parser.add_argument('--public-config',type=Path,required=True)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    web=args.web.resolve()
    release=json.loads((web/'release.config.json').read_text())
    version=(root/'pubspec.yaml').read_text().split('version:',1)[1].splitlines()[0].strip()
    if version!=f'{release["appVersion"]}+{release["androidVersionCode"]}':
        raise SystemExit('Android and web version identities differ.')
    config=args.public_config.read_text()
    for line in config.splitlines():
        if line.strip() and not line.startswith('#') and not line.startswith('VITE_'):
            raise SystemExit('Only public VITE configuration may be embedded.')
    dist=web/'dist'
    source=[dist/'index.html',dist/'manifest.webmanifest',*sorted((dist/'assets').glob('*.js')),
            *sorted((dist/'assets').glob('*.css')),*sorted((dist/'legal').glob('*'))]
    if len(source)<20 or not any(p.name.startswith('release-') and release['appVersion'] in p.read_text() for p in source if p.suffix=='.js'):
        raise SystemExit('The matching complete web production build is missing.')
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
            configurationHash=hashlib.sha256(config.encode()).hexdigest(),
            contentHash=hashlib.sha256(''.join(f'{r["path"]}\0{r["bytes"]}\0{r["sha256"]}\n' for r in rows).encode()).hexdigest(),files=rows)
        (staging/'manifest.json').write_text(json.dumps(manifest,separators=(',',':'))+'\n')
        # This directory is a generated, manifest-owned presentation only.
        shutil.rmtree(destination)
        shutil.copytree(staging,destination)
    print(f'Synced {len(rows)} UI files for {release["appVersion"]}; native core data unchanged.')


if __name__=='__main__':main()
