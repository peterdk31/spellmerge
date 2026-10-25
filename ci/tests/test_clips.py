from __future__ import annotations

import dataclasses
import json
import struct
import subprocess
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest import mock

from smbot import clips, config, screenshots, site

CFG = config.load()


def png(width: int = 4, height: int = 3, colour: tuple[int, int, int, int] = (20, 18, 31, 255), *,
        colour_type: int = 6, interlace: int = 0) -> bytes:
    """A real PNG of one colour, written the way Godot writes them (8-bit RGBA, one IDAT)."""
    pixel = bytes(colour[:4 if colour_type == 6 else 3])
    raw = b"".join(b"\0" + pixel * width for _ in range(height))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, colour_type, 0, 0, interlace)
    return screenshots.PNG_MAGIC + clips._chunk(b"IHDR", ihdr) + clips._chunk(b"IDAT", zlib.compress(raw)) \
        + clips._chunk(b"IEND", b"")


RED, BLUE = png(colour=(224, 89, 47, 255)), png(colour=(59, 115, 201, 255))


def write_clip(root: Path, cid: str, frames: list[bytes], kind: str = "combo", fps: int = 20, **meta: object) -> Path:
    folder = root / cid
    folder.mkdir(parents=True)
    (folder / "meta.json").write_text(json.dumps({"id": cid, "kind": kind, "fps": fps, **meta}))
    for i, data in enumerate(frames):
        (folder / f"frame_{i:04d}.png").write_bytes(data)
    return folder


def chunk_types(data: bytes) -> list[bytes]:
    return [kind for kind, _ in clips._chunks(data)]


class EncodeTest(unittest.TestCase):
    def test_frames_become_a_looping_animated_png(self) -> None:
        data = clips.encode([RED, RED, RED, BLUE, RED], 20)
        chunks = clips._chunks(data)  # every CRC checks out
        self.assertEqual([k for k, _ in chunks],
                         [b"IHDR", b"acTL", b"fcTL", b"IDAT", b"fcTL", b"fdAT", b"fcTL", b"fdAT", b"IEND"])
        self.assertEqual(struct.unpack(">II", chunks[1][1]), (3, 0))  # three frames once merged, loops forever
        controls = [struct.unpack(">IIIIIHHBB", body) for kind, body in chunks if kind == b"fcTL"]
        self.assertEqual([c[5:7] for c in controls], [(3, 20), (1, 20), (1, 20)])  # 3/20 s, then 1/20 s each
        sequence = [c[0] for c in controls] + [struct.unpack(">I", body[:4])[0] for kind, body in chunks
                                               if kind == b"fdAT"]
        self.assertEqual(sorted(sequence), list(range(5)))

    def test_a_decoder_reads_every_frame(self) -> None:
        try:
            from PIL import Image
        except ImportError:
            self.skipTest("Pillow is not installed")
        import io
        image = Image.open(io.BytesIO(clips.encode([RED, BLUE, RED], 10)))
        self.assertEqual(getattr(image, "n_frames", 1), 3)
        seen = []
        for index in range(3):
            image.seek(index)
            seen.append(image.convert("RGBA").getpixel((0, 0)))
        self.assertEqual(seen, [(224, 89, 47, 255), (59, 115, 201, 255), (224, 89, 47, 255)])

    def test_broken_or_unusual_frames_are_refused(self) -> None:
        bad_crc = bytearray(RED)
        bad_crc[-5] ^= 1
        cases = {"not a png": b"GIF89a", "bad crc": bytes(bad_crc), "truncated": RED[:30],
                 "too big": png(641, 3), "palette": png(colour_type=3), "interlaced": png(interlace=1)}
        for name, data in cases.items():
            with self.subTest(name), self.assertRaises(ValueError):
                clips.encode([data], 20)
        with self.assertRaises(ValueError):
            clips.encode([RED, png(5, 3)], 20)  # frames of two sizes
        with self.assertRaises(ValueError):
            clips.encode([], 20)
        self.assertEqual(chunk_types(clips.encode([png(colour_type=2)], 20))[0], b"IHDR")  # RGB is fine


class LoadTest(unittest.TestCase):
    def test_only_clips_that_keep_the_format_are_loaded(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_clip(root, "combo_shatter", [RED, BLUE], title="Shatter @everyone")
            write_clip(root, "element_fire", [RED], kind="element")
            write_clip(root, "wrong_id", [RED]).joinpath("meta.json").write_text('{"id": "x", "kind": "combo", "fps": 20}')
            write_clip(root, "bad_kind", [RED], kind="weapon")
            write_clip(root, "bad_fps", [RED], fps=0)
            write_clip(root, "true_fps", [RED], fps=True)
            write_clip(root, "gap", [RED, RED]).joinpath("frame_0001.png").rename(root / "gap" / "frame_0002.png")
            write_clip(root, "no_frames", [])
            write_clip(root, "Evil Name", [RED])
            (root / "linked").symlink_to(root / "element_fire")
            found = clips.clips_in(root)
            self.assertEqual([c.id for c in found], ["element_fire", "combo_shatter"])  # elements before combos
            self.assertEqual(found[1].title, "Shatter @​everyone")
            self.assertEqual(found[0].title, "Element fire")
            self.assertEqual(clips.clips_in(root / "missing"), [])

    def test_a_clip_over_the_size_limit_is_left_out(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(clips, "MAX_CLIP_BYTES", 100):
            write_clip(Path(tmp), "combo_big", [RED, BLUE, RED, BLUE])
            self.assertEqual(clips.encode_all(Path(tmp), Path(tmp, "out")), {})


class AtlasTest(unittest.TestCase):
    def test_atlas_json_is_checked_and_escaped(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_clip(root, "combo_shatter", [RED, BLUE], title="Shatter")
            write_clip(root, "element_fire", [RED], kind="element", title="Fire")
            (root / "atlas.json").write_text(json.dumps({"entries": [
                {"id": "fire", "kind": "element", "name": "Fire", "description": "Sets enemies alight.",
                 "clips": ["element_fire", "../evil"], "source": "content/spells/elements/fire/fire.tres"},
                {"id": "shatter", "kind": "combo", "name": "<script>alert(1)</script>", "does": "Frost then storm.",
                 "clips": ["combo_shatter"], "source": "../../etc/passwd"},
                {"id": "lightning", "kind": "element", "name": "Lightning"},
                {"id": "fire", "kind": "element", "name": "Duplicate"},
                {"id": "x", "kind": "weapon", "name": "Unknown kind"},
                {"id": "Bad Id", "kind": "form", "name": "Bad id"},
                {"id": "nameless", "kind": "form"},
            ]}))
            count = clips.atlas_page(root, root / "site", "v0.20261026", "o/r")
            page = (root / "site" / "index.html").read_text()
            hashes = json.loads((root / "site" / clips.HASHES).read_text())
        self.assertEqual(count, 2)
        self.assertEqual(sorted(hashes), ["combo_shatter", "element_fire"])
        self.assertNotIn("<script>", page)
        self.assertIn("&lt;script&gt;", page)
        self.assertIn('href="https://github.com/o/r/commits/main/content/spells/elements/fire/fire.tres"', page)
        self.assertNotIn("passwd", page)
        self.assertNotIn("evil", page)
        self.assertNotIn("Duplicate", page)
        self.assertNotIn("Unknown kind", page)
        self.assertIn('<figure id="clip-element_fire"><img src="element_fire.png"', page)
        self.assertIn("Lightning</a></h3><p class=\"none\">No clip yet.</p>", page)
        self.assertLess(page.index("Elements (2)"), page.index("Combos (1)"))
        self.assertIn("v0.20261026", page)

    def test_without_atlas_json_the_clips_are_listed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_clip(root, "reaction_flare_coop", [RED], kind="reaction", title="Flare, two players")
            clips.atlas_page(root, root / "site", "v0", "o/r")
            page = (root / "site" / "index.html").read_text()
        self.assertIn("Reactions (1)", page)
        self.assertIn('src="reaction_flare_coop.png"', page)

    def test_what_changed_since_the_last_atlas(self) -> None:
        self.assertEqual(clips.changed({"a": "1", "b": "2", "c": "3"}, {"a": "1", "b": "9", "gone": "4"}),
                         (["c"], ["b"]))
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / clips.HASHES).write_text(json.dumps({"ok": "1", "Bad Id": "2", "num": 3}))
            self.assertEqual(clips.read_hashes(Path(tmp)), {"ok": "1"})
            self.assertEqual(clips.read_hashes(Path(tmp, "missing")), {})
            self.assertEqual(clips.read_hashes(None), {})

    def test_the_site_copies_only_atlas_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            published, out = Path(tmp, "published"), Path(tmp, "site")
            self.assertEqual(site.copy_atlas(published, out), 0)  # nothing published yet
            published.mkdir()
            for name in ("index.html", "hashes.json", "combo_shatter.png", "evil.js", "Bad Name.png"):
                (published / name).write_text("x")
            self.assertEqual(site.copy_atlas(published, out), 3)
            self.assertEqual(sorted(p.name for p in out.iterdir()), ["combo_shatter.png", "hashes.json", "index.html"])


class PublishTest(unittest.TestCase):
    def test_the_daily_run_posts_only_what_changed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root, previous = Path(tmp, "clips"), Path(tmp, "previous")
            write_clip(root, "combo_shatter", [RED, BLUE], title="Shatter")
            write_clip(root, "element_fire", [RED], kind="element", title="Fire")
            write_clip(root, "form_bolt", [BLUE], kind="form", title="Bolt")
            previous.mkdir()
            with tempfile.TemporaryDirectory() as other:
                clips.atlas_page(root, Path(other), "v0", "o/r")
                old = json.loads((Path(other) / clips.HASHES).read_text())
            old["combo_shatter"] = "an older recording"
            del old["element_fire"]
            (previous / clips.HASHES).write_text(json.dumps(old))
            pushed: dict[str, bytes] = {}

            def push(cfg: object, token: str, files: list[Path], prefix: str, remote: str = "", **kw: object) -> str:
                pushed.update({f.name: f.read_bytes() for f in files})  # the files are gone once publish returns
                return "c0ffee"

            with mock.patch.object(clips.screenshots, "push", side_effect=push) as pusher, \
                    mock.patch.object(clips.dailylog, "post") as post:
                clips.publish(CFG, "t", root, previous, "v0.20261026")
                self.assertEqual(pusher.call_args.args[3], clips.ATLAS)
                self.assertTrue(pusher.call_args.kwargs["clear"])
                self.assertEqual(sorted(pushed),
                                 ["combo_shatter.png", "element_fire.png", "form_bolt.png", "hashes.json", "index.html"])
                lines, extra = post.call_args.args[2], post.call_args.kwargs["extra"]
                self.assertIn("1 new, 1 changed, 3 in all", lines[0])
                self.assertIn(f"{CFG.pages}/atlas/", lines[0])
                self.assertIn(f"https://raw.githubusercontent.com/{CFG.repo}/c0ffee/atlas/combo_shatter.png", extra)
                self.assertIn("/atlas/element_fire.png", extra)
                self.assertIn(f"{CFG.pages}/atlas/#clip-combo_shatter", extra)
                self.assertNotIn("form_bolt", extra)
                self.assertLess(extra.index("Shatter"), extra.index("Fire"))  # changed before new

                post.reset_mock()
                (previous / clips.HASHES).write_bytes(pushed["hashes.json"])  # what the branch now holds
                clips.publish(CFG, "t", root, previous, "v0.20261027")
                post.assert_not_called()  # the same clips again: the atlas is renewed, nothing is posted
                self.assertEqual(pusher.call_count, 2)

    def test_nothing_recorded_changes_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(clips.screenshots, "push") as push, \
                mock.patch.object(clips.dailylog, "post") as post:
            clips.publish(CFG, "t", Path(tmp, "missing"), None, "v0")
        push.assert_not_called()
        post.assert_not_called()

    def test_push_can_replace_what_was_there(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            origin = Path(tmp, "origin.git")
            subprocess.run(["git", "init", "-q", "--bare", str(origin)], check=True)
            for name in ("old.png", "new.png", "keep.png"):
                Path(tmp, name).write_bytes(RED)
            cfg = dataclasses.replace(CFG, bot=config.Identity("test-bot[bot]", 1))
            screenshots.push(cfg, "t", [Path(tmp, "keep.png")], "pr-7/abc1234", str(origin))
            screenshots.push(cfg, "t", [Path(tmp, "old.png")], "atlas", str(origin), clear=True)
            last = screenshots.push(cfg, "t", [Path(tmp, "new.png")], "atlas", str(origin), clear=True)
            files = subprocess.run(["git", "-C", str(origin), "ls-tree", "-r", "--name-only", last],
                                   check=True, capture_output=True, text=True).stdout.split()
        self.assertEqual(files, ["atlas/new.png", "pr-7/abc1234/keep.png"])


class PullRequestTest(unittest.TestCase):
    def artifact(self, tmp: str, chosen: list, after: dict[str, list[bytes]], before: dict[str, list[bytes]]) -> Path:
        root = Path(tmp, "shots")
        root.mkdir()
        (root / "clips.json").write_text(json.dumps(chosen))
        for side, made in (("after", after), ("before", before)):
            for cid, frames in made.items():
                write_clip(root / side / "clips", cid, frames, title=cid.replace("_", " ").title())
        return root

    def test_only_chosen_clips_that_changed_are_shown(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = self.artifact(tmp, [{"id": "combo_shatter", "caption": "Shatter has a burst @everyone"},
                                       {"id": "combo_same", "caption": "x"}, {"id": "combo_new", "caption": "New"},
                                       {"id": "../evil", "caption": "x"}, {"id": "combo_unrecorded", "caption": "x"}],
                                 after={"combo_shatter": [RED, BLUE], "combo_same": [RED], "combo_new": [BLUE],
                                        "combo_unchosen": [RED]},
                                 before={"combo_shatter": [RED], "combo_same": [RED]})
            shown = clips.pairs(root, Path(tmp, "work"))
            self.assertEqual([(c.id, old is not None) for _, c, _, old in shown],
                             [("combo_shatter", True), ("combo_new", False)])
            text = clips.section("https://x/base", shown)
        self.assertTrue(text.startswith(clips.HEADING))
        self.assertIn("**Shatter has a burst @​everyone**", text)
        self.assertIn("| ![before](https://x/base/before/combo_shatter.png) | ![after](https://x/base/after/combo_shatter.png) |",
                      text)
        self.assertIn("New: *Combo New*", text)

    def test_a_pr_with_only_clips_still_gets_its_comment(self) -> None:
        posted: list = []

        def api(path: str, *args: str, input: dict | None = None) -> object:
            posted.append((path, input["body"]))
            return {}

        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(screenshots.gh, "api", api), \
                mock.patch.object(screenshots, "push", return_value="c0ffee") as push:
            root = self.artifact(tmp, [{"id": "combo_shatter", "caption": "The burst"}],
                                 after={"combo_shatter": [RED, BLUE]}, before={"combo_shatter": [RED]})
            screenshots.post(CFG, "t", 7, "abc1234def", root)
        self.assertEqual(push.call_args.kwargs["names"], ["clips/after/combo_shatter.png", "clips/before/combo_shatter.png"])
        body = posted[0][1]
        self.assertTrue(body.startswith(screenshots.HEADING))  # so the Daily log repeats it (for_log)
        self.assertIn(f"/c0ffee/pr-7/abc1234/clips/after/combo_shatter.png", body)
        self.assertIn(clips.HEADING, body)


if __name__ == "__main__":
    unittest.main()
