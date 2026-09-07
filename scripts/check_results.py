#!/usr/bin/env python3
"""Require real passing test cases, expected skips and named acceptance checks."""

import argparse
import fnmatch
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


def check_results(path, required=(), allow_skips=()):
    root = ET.parse(path).getroot()
    if root.tag not in {'testsuite', 'testsuites'}:
        raise ValueError(f'unsupported XML root: {root.tag}')
    cases = list(root.iter('testcase'))
    if not cases:
        raise ValueError('no test cases')
    outcomes = {'pass': [], 'fail': [], 'skip': []}
    seen = set()
    for case in cases:
        name = case.get('name', '')
        identity = (case.get('classname', ''), name)
        if not name or identity in seen:
            raise ValueError(f'duplicate test or empty test name: {name!r}')
        seen.add(identity)
        state = ('fail' if case.find('failure') is not None or case.find('error') is not None
                 else 'skip' if case.find('skipped') is not None else 'pass')
        outcomes[state].append(name)
    if outcomes['fail']:
        raise ValueError('failed tests: ' + ', '.join(outcomes['fail']))
    if not outcomes['pass']:
        raise ValueError('no passing tests')
    for name in required:
        if name not in outcomes['pass']:
            raise ValueError(f'required test did not pass: {name}')
    for name in outcomes['skip']:
        if not any(fnmatch.fnmatchcase(name, pattern) for pattern in allow_skips):
            raise ValueError(f'unexpected skip: {name}')
    return outcomes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xml', type=Path)
    parser.add_argument('--require', action='append', default=[])
    parser.add_argument('--allow-skip', action='append', default=[])
    parser.add_argument('--profile', choices=['software', 'rtl', 'rom', 'gate', 'dead-rom'])
    parser.add_argument('--json-output', type=Path)
    args = parser.parse_args()
    try:
        if args.profile:
            profiles = json.loads((Path(__file__).resolve().parents[1] / 'test/coverage.json').read_text())
            profile = profiles[args.profile]
            args.require.extend(profile['required'])
            args.allow_skip.extend(profile['allowed_skips'])
            if profile.get('include_common'):
                args.require.extend(profiles['common_required'])
            for mode in profile.get('directed_modes', []):
                prefix = 'test_directed_' if mode == 'rom' else 'test_flash_directed_'
                args.require.extend(f'{prefix}{name}_fwd{fwd}'
                                    for name in profiles['directed_programs'] for fwd in (1, 0))
        outcomes = check_results(args.xml, args.require, args.allow_skip)
        print(f"TESTS={sum(map(len, outcomes.values()))} PASS={len(outcomes['pass'])} "
              f"FAIL={len(outcomes['fail'])} SKIP={len(outcomes['skip'])}")
        if args.json_output:
            args.json_output.write_text(json.dumps(outcomes, indent=2) + '\n')
        return 0
    except (OSError, ET.ParseError, ValueError, KeyError) as error:
        print(f'test evidence rejected: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
