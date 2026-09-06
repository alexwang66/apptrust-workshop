#!/usr/bin/env python3
"""Generate evidence from real test cases; fail closed on empty or nonpassing reports."""
import hashlib
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def convert(path):
    raw = Path(path).read_bytes()
    cases = list(ET.fromstring(raw).iter('testcase'))
    if not cases:
        raise ValueError('No test cases in JUnit report')
    tests = []
    for case in cases:
        status = next((name for name in ('failure', 'error', 'skipped')
                       if case.find(name) is not None), 'passed')
        tests.append({'name': case.get('name', ''), 'class': case.get('classname', ''),
                      'status': status, 'time': case.get('time', '0')})
    if any(t['status'] != 'passed' for t in tests):
        raise ValueError('Evidence requires all tests to pass, with no skipped tests')
    return {'testReport': {'summary': {'totalTests': len(tests), 'totalFailures': 0,
            'totalErrors': 0, 'totalSkipped': 0, 'successRate': 100}, 'testSuites': tests},
            'reportSha256': hashlib.sha256(raw).hexdigest()}


if __name__ == '__main__':
    output = Path(sys.argv[2])
    output.unlink(missing_ok=True)
    output.write_text(json.dumps(convert(sys.argv[1]), indent=2) + '\n')
