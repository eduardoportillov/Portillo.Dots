"""Structure of the CI workflow: the platform matrix is a tested contract."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CiWorkflowTests(unittest.TestCase):
    """The workflow is the contract for the platform matrix, so assert on it."""

    def test_workflow_declares_the_supported_platform_matrix(self):
        path = ROOT / '.github/workflows/ci.yml'
        self.assertTrue(path.is_file())
        text = path.read_text()
        self.assertNotIn('\t', text, 'YAML must use spaces, not tabs')
        for expected in ['ubuntu-latest', 'macos-latest', 'actions/checkout@v4',
                         'actions/setup-python@v5', 'fetch-depth: 0']:
            self.assertIn(expected, text)
        self.assertNotIn('windows-latest', text,
                         'Windows is explicitly out of scope; see docs/platforms.md')

    def test_workflow_runs_tests_shellcheck_and_the_secret_scan(self):
        text = (ROOT / '.github/workflows/ci.yml').read_text()
        for job in ['tests:', 'shellcheck:', 'secret-scan:']:
            self.assertIn(job, text, f'missing CI job: {job}')
        self.assertIn('unittest discover', text)
        self.assertIn('test_shellcheck.py', text)
        self.assertIn('test_security.py', text)

    def test_workflow_has_no_pull_request_write_permissions(self):
        text = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertIn('permissions:', text)
        self.assertIn('contents: read', text)
        self.assertNotIn('write', text.split('permissions:', 1)[1].split('jobs:', 1)[0],
                         'CI must not request write permissions')
