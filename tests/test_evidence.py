import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('evidence', 'scripts/junit-evidence.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class EvidenceTests(unittest.TestCase):
    def convert(self, xml):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'report.xml'
            path.write_text(xml)
            return module.convert(path)

    def test_nested_suites_count_cases_once(self):
        result = self.convert('<testsuites><testsuite><testsuite><testcase name="ok"/></testsuite></testsuite></testsuites>')
        self.assertEqual(result['testReport']['summary']['totalTests'], 1)
        self.assertEqual(len(result['reportSha256']), 64)

    def test_empty_rejected(self):
        with self.assertRaises(ValueError):
            self.convert('<testsuites/>')

    def test_nonpassing_rejected_even_with_passing_summary(self):
        for status in ('failure', 'error', 'skipped'):
            with self.subTest(status=status), self.assertRaises(ValueError):
                self.convert(f'<testsuite failures="0"><testcase><{status}/></testcase></testsuite>')

    def test_malformed_rejected(self):
        with self.assertRaises(Exception):
            self.convert('<testsuite>')
