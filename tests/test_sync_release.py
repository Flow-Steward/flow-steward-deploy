"""Offline checks of the pin rewrite and the consistency guard."""

import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "sync-release.py"
spec = importlib.util.spec_from_file_location("sync_release", SCRIPT)
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)

OLD = "a" * 64
NEW = "b" * 64
PINS = {
    "COMPACT_IMAGE": f"ghcr.io/flow-steward/flow-steward-compact@sha256:{NEW}",
    "POSTGRES_IMAGE": f"ghcr.io/flow-steward/flow-steward-postgres@sha256:{NEW}",
    "RABBITMQ_IMAGE": f"rabbitmq@sha256:{NEW}",
}


class RewriteTest(unittest.TestCase):
    def test_rewrites_each_image_and_leaves_others(self):
        text = (
            f"image: ghcr.io/flow-steward/flow-steward-compact@sha256:{OLD}\n"
            f"url: ghcr.io/flow-steward/flow-steward-postgres@sha256:{OLD}\n"
            f"image = 'rabbitmq@sha256:{OLD}'\n"
            f"other: example.org/team/rabbitmq@sha256:{OLD}\n"
        )
        updated = sync.rewrite(text, PINS)
        self.assertEqual(updated.count(NEW), 3)
        self.assertIn(f"example.org/team/rabbitmq@sha256:{OLD}", updated)


class ProblemsTest(unittest.TestCase):
    def check(self, name, text):
        with tempfile.TemporaryDirectory() as directory:
            original = sync.ROOT
            sync.ROOT = Path(directory)
            try:
                path = Path(directory) / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
                return sync.problems([path], PINS)
            finally:
                sync.ROOT = original

    def test_current_pins_pass(self):
        self.assertEqual(self.check("render.yaml", f"url: {PINS['COMPACT_IMAGE']}\n"), [])

    def test_stale_pin_fails(self):
        issues = self.check("render.yaml", f"url: ghcr.io/flow-steward/flow-steward-compact@sha256:{OLD}\n")
        self.assertEqual(len(issues), 1)

    def test_mutable_tag_fails(self):
        issues = self.check("fly/compact.toml", "image = 'ghcr.io/flow-steward/flow-steward-compact:latest'\n")
        self.assertIn("is a tag", issues[0])

    def test_hand_written_release_number_fails(self):
        issues = self.check("railway/README.md", "Installs Flow Steward 0.9.13 images.\n")
        self.assertIn("hand-written release number", issues[0])

    def test_addresses_and_prices_are_not_versions(self):
        text = "Proxy to 172.17.0.1:3000 for $140.25/month.\n"
        self.assertEqual(self.check("README.md", text), [])

    def test_tests_may_use_fixture_versions(self):
        self.assertEqual(self.check("tests/vps-install.sh", "RELEASE_TAG=v7.8.9\n"), [])


class ReleaseFileTest(unittest.TestCase):
    def test_render_lists_every_image(self):
        rendered = sync.render_release("1.2.3", PINS)
        self.assertIn("FLOW_STEWARD_RELEASE=1.2.3\n", rendered)
        for value in PINS.values():
            self.assertIn(value, rendered)


if __name__ == "__main__":
    unittest.main()
