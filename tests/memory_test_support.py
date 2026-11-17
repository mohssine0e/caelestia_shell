"""Shared setup for the personal-memory tests: synthetic data in a temp dir only."""

import os
import sys
import tempfile

SCRIPTS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scripts")
if SCRIPTS not in sys.path:
    sys.path.insert(0, SCRIPTS)


class TempConfig:
    """Point user_facts at a fresh temp directory for one test."""

    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="caelestia-test-")
        self.dir = os.path.join(self.tmp.name, "caelestia")
        self._old = os.environ.get("CAELESTIA_CONFIG_DIR")
        os.environ["CAELESTIA_CONFIG_DIR"] = self.dir

    def path(self, name):
        return os.path.join(self.dir, name)

    def write(self, name, text):
        os.makedirs(self.dir, exist_ok=True)
        full = self.path(name)
        with open(full, "w", encoding="utf-8") as handle:
            handle.write(text)
        return full

    def close(self):
        if self._old is None:
            os.environ.pop("CAELESTIA_CONFIG_DIR", None)
        else:
            os.environ["CAELESTIA_CONFIG_DIR"] = self._old
        self.tmp.cleanup()
