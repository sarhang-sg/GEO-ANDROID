#!/usr/bin/env python3
"""Require actual completed Dart tests, with no failed or skipped test cases."""
import argparse
import json
from pathlib import Path

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('report',type=Path)
parser.add_argument('--minimum',type=int,required=True)
args=parser.parse_args()
events=[]
for line in args.report.read_text().splitlines():
    while line.startswith('Running build hooks...'):
        line=line[len('Running build hooks...'):]
    if not line.strip():
        continue
    value=json.loads(line)
    events.extend(value if isinstance(value,list) else [value])
if any(not isinstance(event,dict) for event in events):
    raise SystemExit('Unexpected machine report record.')
tests=[e for e in events if e.get('type')=='testDone' and not e.get('hidden')]
if len(tests)<args.minimum or any(e.get('skipped') or e.get('result')!='success' for e in events if e.get('type')=='testDone'):
    raise SystemExit('Test report contains missing, failed or skipped cases.')
if not any(e.get('type')=='done' and e.get('success') is True for e in events):
    raise SystemExit('Test runner did not complete successfully.')
print(f'PASS {len(tests)} completed tests / zero failures / zero skipped.')
