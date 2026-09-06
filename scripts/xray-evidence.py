#!/usr/bin/env python3
"""Turn a successful JFrog Xray JSON scan into AppTrust security evidence."""
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def convert(path, image, project):
    raw = Path(path).read_bytes()
    scan = json.loads(raw)
    if not isinstance(scan, (dict, list)):
        raise ValueError('Xray scan output must be a JSON object or array')
    return {
        'scanner': {'name': 'JFrog Xray'},
        'target': {'type': 'docker', 'image': image},
        'project': project,
        'policyResult': 'PASS',
        'scannedAt': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'reportSha256': hashlib.sha256(raw).hexdigest(),
        'scan': scan,
    }


if __name__ == '__main__':
    output = Path(sys.argv[2])
    output.unlink(missing_ok=True)
    output.write_text(json.dumps(convert(sys.argv[1], sys.argv[3], sys.argv[4]), indent=2) + '\n')
