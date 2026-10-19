"""Documentation must not describe the local patch flow that was removed."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class OtiringDocsTests(unittest.TestCase):
    def test_no_reference_to_the_removed_patch_flow_survives(self):
        tracked = subprocess.check_output(
            ["git", "-C", str(ROOT), "ls-files", "-z"]).decode().split("\\0")
        offenders = [n for n in tracked if n.startswith("o-tiling/patches/")]
        self.assertEqual(offenders, [], "the patches directory must be gone")
        for name in ["o-tiling/install.sh", "o-tiling/README.md", "README.md",
                     "docs/hardware-otiling.md", "TODO.md"]:
            path = ROOT / name
            if not path.exists():
                continue
            text = path.read_text()
            for needle in ["apply-patches.sh", "PATCH 1", "PATCH 2", "same_monitor_window"]:
                self.assertNotIn(needle, text,
                                 f"{name} still documents the removed patch flow")

    def test_acceptance_protocol_is_documented(self):
        readme = (ROOT / "o-tiling/README.md").read_text()
        for expected in ["verify.sh", "upstream", "v2.12.01", "Ctrl+Alt", "Shift+Alt"]:
            self.assertIn(expected, readme)
        todo = (ROOT / "TODO.md").read_text()
        self.assertIn("v2.12.01", todo)
        self.assertIn("oliwebd/o-tiling/issues/50", todo)


if __name__ == "__main__":
    unittest.main()
