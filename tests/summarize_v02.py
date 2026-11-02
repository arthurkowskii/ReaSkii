#!/usr/bin/env python3
"""Aggregate actual 0.2 native evidence; reject stale inputs and wrong totals."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def summarize():
    inputs = {'theme_sha256': ROOT / 'dist/ReaSkii.ReaperThemeZip',
              'suite_sha256': ROOT / 'tests/native_v02.lua',
              'defaults_sha256': ROOT / 'scripts/ReaSkii_Defaults.lua'}
    expected = {name: sha(path) for name, path in inputs.items()}
    reports = []
    for width in (960, 640, 540, 320):
        path = ROOT / f'qa/v02-native-{width}.tsv'
        lines = [l.split('\t') for l in path.read_text().splitlines()]
        meta = {p[1]: p[2] for p in lines if p[0] == 'META'}
        assert meta == expected, f'Stale native inputs: {path}'
        counts = {kind: sum(p[0] == kind for p in lines) for kind in ('PASS', 'FAIL', 'ERROR', 'CASE', 'DONE')}
        assert counts['DONE'] == 1 and counts['FAIL'] == counts['ERROR'] == 0, counts
        done = next(p for p in lines if p[0] == 'DONE')
        assert [counts['PASS'], counts['FAIL'], counts['CASE']] == list(map(int, done[1:])), path
        reports.append({'width': width, 'tcp_cases': counts['CASE'], 'assertions': counts['PASS'],
                        'failures': 0, 'factory_parameters': sum(p[0]=='PASS' and p[1].startswith('factory ') for p in lines),
                        'required_rectangles': sum(p[0]=='PASS' and 'required two-row ' in p[1] for p in lines),
                        'report_sha256': sha(path)})
    result = {'version': '0.2.0', 'engine': 'Reapertips v1.95a Dark', 'runtime': 'REAPER 7.84 Linux/Xvfb',
              'inputs': expected, 'reports': reports, 'tcp_cases': sum(r['tcp_cases'] for r in reports),
              'assertions': sum(r['assertions'] for r in reports),
              'required_rectangles': sum(r['required_rectangles'] for r in reports),
              'failures': 0, 'original_reark_assets': 2892}
    (ROOT / 'qa/summary-v02.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return result


if __name__ == '__main__':
    summarize()
