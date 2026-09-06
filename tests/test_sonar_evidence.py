import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('sonar_evidence', 'scripts/sonar-evidence.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SonarEvidenceTests(unittest.TestCase):
    def test_valid_quality_gate_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            task = Path(directory) / 'report-task.txt'
            gate = Path(directory) / 'quality-gate.json'
            task.write_text(
                'projectKey=alexwang66_apptrust-workshop\n'
                'serverUrl=https://sonarcloud.io\n'
                'dashboardUrl=https://sonarcloud.io/dashboard?id=alexwang66_apptrust-workshop\n'
                'ceTaskId=task-1\n'
            )
            gate.write_text(json.dumps({'projectStatus': {'status': 'OK', 'conditions': []}}))
            result = module.convert(task, gate)
        self.assertEqual(result['scanner']['name'], 'SonarQube')
        self.assertEqual(result['policyResult'], 'PASS')
        self.assertEqual(result['analysis']['projectKey'], 'alexwang66_apptrust-workshop')
        self.assertEqual(len(result['qualityGateSha256']), 64)

    def test_nonpassing_quality_gate_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            task = Path(directory) / 'report-task.txt'
            gate = Path(directory) / 'quality-gate.json'
            task.write_text('projectKey=project\n')
            gate.write_text(json.dumps({'projectStatus': {'status': 'ERROR', 'conditions': []}}))
            with self.assertRaises(ValueError):
                module.convert(task, gate)

    def test_missing_project_status_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            task = Path(directory) / 'report-task.txt'
            gate = Path(directory) / 'quality-gate.json'
            task.write_text('projectKey=project\n')
            gate.write_text('{}')
            with self.assertRaises(ValueError):
                module.convert(task, gate)
