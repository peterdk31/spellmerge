from __future__ import annotations

import unittest

from smbot import websmoke


class WebSmokeTest(unittest.TestCase):
    PAGE = 'const GODOT_CONFIG = {"args":[],"canvasResizePolicy":2,"executable":"index"};'

    def test_page_args_fill_the_start_config(self) -> None:
        out = websmoke.with_page_args(self.PAGE, ["--four-bot"])
        self.assertIn('{"args":["--four-bot"],"canvasResizePolicy":2', out)

    def test_page_args_fail_without_an_args_slot(self) -> None:
        with self.assertRaises(ValueError):
            websmoke.with_page_args("<html>no config</html>", ["--four-bot"])

    def test_page_args_parse_with_an_equals_sign(self) -> None:
        # main() stops at "Chrome is not installed" or runs; only the parsing is checked here.
        from unittest import mock
        with mock.patch.object(websmoke, "find_chrome", return_value=None):
            self.assertEqual(websmoke.main(["build", "--expect", "x", "--page-args=--four-bot"]), 2)
        with self.assertRaises(SystemExit):
            websmoke.main(["build", "--expect", "x", "--page-args", "--four-bot"])

    def test_a_fast_load_gives_no_warning(self) -> None:
        self.assertIsNone(websmoke.load_warning(3.0, 10.0))
        self.assertIsNone(websmoke.load_warning(30.0, None))

    def test_a_slow_load_warns_with_fixes_and_never_fails(self) -> None:
        warning = websmoke.load_warning(12.5, 10.0)
        self.assertIsNotNone(warning)
        self.assertIn("12.5 s", warning)
        self.assertIn("Not a failure", warning)
        self.assertIn("(1)", warning)

    def test_warn_load_replaces_max_load(self) -> None:
        from unittest import mock
        with mock.patch.object(websmoke, "find_chrome", return_value=None):
            self.assertEqual(websmoke.main(["build", "--expect", "x", "--warn-load", "10"]), 2)
        with self.assertRaises(SystemExit):
            websmoke.main(["build", "--expect", "x", "--max-load", "10"])


if __name__ == "__main__":
    unittest.main()
