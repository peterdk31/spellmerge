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


if __name__ == "__main__":
    unittest.main()
