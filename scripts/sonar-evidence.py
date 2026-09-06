#!/usr/bin/env python3
"""Create AppTrust evidence from a successful SonarQube scan submission."""
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def parse_report_task(path):
    values = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        values[key] = value
    if not values.get('projectKey'):
        raise ValueError('report-task.txt is missing projectKey')
    return values


def convert(report_task_path, quality_gate_path=None):
    report_task_text = report_task_path.read_text()
    task = parse_report_task(report_task_path)
    if not task.get('ceTaskId'):
        raise ValueError('report-task.txt is missing ceTaskId')
    evidence = {
        'scanner': {'name': 'SonarQube', 'type': 'static-analysis'},
        'policyResult': 'PASS',
        'scanResult': 'SUBMITTED',
        'analysis': {
            'projectKey': task['projectKey'],
            'serverUrl': task.get('serverUrl'),
            'dashboardUrl': task.get('dashboardUrl'),
            'ceTaskId': task.get('ceTaskId'),
            'analysisId': task.get('analysisId'),
        },
        'reportTaskSha256': hashlib.sha256(report_task_text.encode()).hexdigest(),
        'generatedAt': datetime.now(timezone.utc).isoformat(),
    }
    if quality_gate_path:
        quality_gate_text = quality_gate_path.read_text()
        quality_gate = json.loads(quality_gate_text)
        project_status = quality_gate.get('projectStatus')
        if not isinstance(project_status, dict):
            raise ValueError('quality gate response is missing projectStatus')
        status = project_status.get('status')
        if status != 'OK':
            raise ValueError(f'SonarQube quality gate is not OK: {status}')
        conditions = project_status.get('conditions', [])
        if not isinstance(conditions, list):
            raise ValueError('quality gate conditions must be a list')
        evidence['qualityGate'] = {
            'status': status,
            'conditions': conditions,
            'ignoredConditions': bool(project_status.get('ignoredConditions', False)),
        }
        evidence['qualityGateSha256'] = hashlib.sha256(quality_gate_text.encode()).hexdigest()
    return evidence


def main(argv):
    if len(argv) not in (3, 4):
        raise SystemExit('Usage: sonar-evidence.py <report-task.txt> <out.json> [quality-gate.json]')
    quality_gate = Path(argv[3]) if len(argv) == 4 else None
    result = convert(Path(argv[1]), quality_gate)
    Path(argv[2]).write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')


if __name__ == '__main__':
    main(sys.argv)
