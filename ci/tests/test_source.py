import unittest
import warnings
from pathlib import Path

CI = Path(__file__).resolve().parents[1]


class SourceTest(unittest.TestCase):
    def test_every_script_compiles_without_warnings(self) -> None:
        # An invalid escape like "\`" is only a SyntaxWarning now and becomes an error in a later Python.
        for path in sorted(CI.rglob("*.py")):
            with self.subTest(path=path.relative_to(CI)), warnings.catch_warnings():
                warnings.simplefilter("error")
                compile(path.read_text(encoding="utf-8"), str(path), "exec")


if __name__ == "__main__":
    unittest.main()
