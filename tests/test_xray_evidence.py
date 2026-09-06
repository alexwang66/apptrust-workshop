import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('xray_evidence', 'scripts/xray-evidence.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class XrayEvidenceTests(unittest.TestCase):
    def test_valid_scan_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'scan.json'
            path.write_text(json.dumps({'vulnerabilities': [], 'violations': []}))
            result = module.convert(path, 'registry/repo/image:1.0.0', 'alex')
        self.assertEqual(result['scanner']['name'], 'JFrog Xray')
        self.assertEqual(result['policyResult'], 'PASS')
        self.assertEqual(result['scan']['violations'], [])
        self.assertEqual(len(result['reportSha256']), 64)

    def test_invalid_json_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'scan.json'
            path.write_text('not-json')
            with self.assertRaises(json.JSONDecodeError):
                module.convert(path, 'image', 'alex')

    def test_scalar_json_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'scan.json'
            path.write_text('true')
            with self.assertRaises(ValueError):
                module.convert(path, 'image', 'alex')
