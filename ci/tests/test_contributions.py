from __future__ import annotations

import datetime as dt
import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

from smbot import cla, claims, communitymerge, quarantine, rate, submissions, triage, votes

T0 = dt.datetime(2026, 10, 17, 12, 0, tzinfo=dt.timezone.utc)
S = votes.VoteSettings()


def png(width: int, height: int, extra: bytes = b"") -> bytes:
    raw = b"".join(b"\0" + b"\x10\x20\x30\xff" * width for _ in range(height))
    return (submissions.PNG_SIG + submissions._chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + submissions._chunk(b"tEXt", b"Comment\0hidden payload") + submissions._chunk(b"IDAT", zlib.compress(raw))
            + submissions._chunk(b"IEND", b"") + extra)


class VotesTest(unittest.TestCase):
    def test_needed_matches_the_plan_table(self) -> None:
        for n, want in [(0, 0), (2, 0), (3, 2), (13, 2), (14, 3), (20, 3), (50, 8), (100, 15), (167, 25), (500, 25)]:
            self.assertEqual(votes.needed(n, S), want, n)

    def vote(self, login: str, up: bool, minutes: int = 0) -> votes.Vote:
        return votes.Vote(login, up, T0 + dt.timedelta(minutes=minutes))

    def test_approval_needs_count_and_share(self) -> None:
        cast = [self.vote(f"u{i}", True, i * 30) for i in range(3)] + [self.vote("d1", False, 200),
                                                                        self.vote("d2", False, 300)]
        t = votes.tally(cast, {v.login for v in cast}, set(), 18, S)
        self.assertEqual((t.up, t.down, t.needed), (3, 2, 3))
        self.assertTrue(t.approved(S))  # 3 >= 3 and 60% >= 60%
        cast.append(self.vote("d3", False, 400))
        t = votes.tally(cast, {v.login for v in cast}, set(), 18, S)
        self.assertFalse(t.approved(S))  # 50% < 60%

    def test_latest_vote_counts_and_ineligible_are_listed(self) -> None:
        cast = [self.vote("a", True, 0), self.vote("a", False, 5), self.vote("b", True, 10)]
        t = votes.tally(cast, {"a"}, set(), 10, S)
        self.assertEqual((t.up, t.down, t.ineligible), (0, 1, ["b"]))

    def test_coordinated_burst_from_newcomers_is_discounted(self) -> None:
        burst = [self.vote(f"new{i}", True, i) for i in range(4)]
        regular = [self.vote("old", True, 1)]
        t = votes.tally(burst + regular, {v.login for v in burst + regular}, {f"new{i}" for i in range(4)}, 20, S)
        self.assertEqual(t.up, 1)
        self.assertEqual(len(t.discounted), 4)

    def test_window_and_decision(self) -> None:
        t = votes.Tally(1, 0, 3, 18)
        self.assertEqual(votes.window(T0, T0 + dt.timedelta(hours=5), t).state, "open")
        self.assertEqual(votes.window(T0, T0 + dt.timedelta(hours=30), t).state, "extended")
        closed = votes.window(T0, T0 + dt.timedelta(hours=49), t)
        self.assertEqual(closed.state, "closed")
        self.assertEqual(votes.decision(t, closed, S, 3.9), "merge")  # Claude alone, stricter bar met
        self.assertEqual(votes.decision(t, closed, S, 3.6), "close")
        self.assertEqual(votes.decision(votes.Tally(0, 0, 0, 2), closed, S, 3.5), "merge")  # no voters: no wait
        self.assertEqual(votes.decision(t, votes.window(T0, T0, t), S, 4.0), "wait")

    def test_status_line(self) -> None:
        t = votes.Tally(4, 1, 3, 18)
        w = votes.Window("open", 14.2)
        self.assertEqual(votes.status_line(t, w, S), "4 👍 / 1 👎, needs 3 👍 (15% of 18 active voters), 14 hours left")

    def test_eligibility(self) -> None:
        old = {"created_at": "2020-01-01T00:00:00Z", "public_repos": 1, "public_gists": 0, "followers": 0}
        new = {**old, "created_at": "2026-10-10T00:00:00Z"}
        idle = {**old, "public_repos": 0}
        self.assertTrue(votes.open_phase_eligible(old, T0))
        self.assertFalse(votes.open_phase_eligible(new, T0))
        self.assertFalse(votes.open_phase_eligible(idle, T0))
        self.assertTrue(votes.community_phase_eligible(T0 - dt.timedelta(days=8), T0))
        self.assertFalse(votes.community_phase_eligible(T0 - dt.timedelta(days=3), T0))
        self.assertEqual(votes.phase(19), "open")
        self.assertEqual(votes.phase(20), "community")


class RatingTest(unittest.TestCase):
    def rating(self, decision: str = "merge", **scores: int) -> dict:
        s = {c: 4 for c in rate.CRITERIA}
        s.update(scores)
        return {"scores": s, "decision": decision, "summary": "Adds a frost bolt.", "message": "Thanks!",
                "area_answers": [], "change_requests": [], "fixups": [], "concerns": []}

    def test_thresholds(self) -> None:
        self.assertEqual(rate.final_decision(self.rating()), "merge")
        self.assertEqual(rate.final_decision(self.rating(risk=1)), "changes")  # a criterion below 2
        self.assertEqual(rate.final_decision(self.rating(fit=2, fun=2, value=2, quality=3)), "changes")  # avg < 3.5
        self.assertEqual(rate.final_decision(self.rating("close")), "close")
        self.assertEqual(rate.final_decision(self.rating("changes", fit=5)), "changes")

    def test_marker_roundtrip_and_rated_shas(self) -> None:
        pr = {"user": {"login": "ann"}, "head": {"sha": "abc123"}}
        body = rate.comment_body(pr, self.rating(), "merge", None)
        self.assertEqual(rate.parse_marker(body), {"sha": "abc123", "decision": "merge", "average": "4.00"})
        comments = [{"user": {"login": "spellmerge-bot[bot]"}, "body": body},
                    {"user": {"login": "mallory"}, "body": rate.marker("fff", "merge", 5)}]
        self.assertEqual(triage.rated_at(comments, "spellmerge-bot[bot]"), {"abc123"})
        found = communitymerge.latest_rating(comments, "spellmerge-bot[bot]")
        self.assertEqual(found[1]["sha"], "abc123")

    def test_vote_line_is_replaced(self) -> None:
        pr = {"user": {"login": "ann"}, "head": {"sha": "abc"}}
        body = rate.comment_body(pr, self.rating(), "merge", "Voting is open.")
        updated = communitymerge.replace_vote_line(body, "2 👍 / 0 👎, needs 2 👍")
        self.assertIn("2 👍 / 0 👎, needs 2 👍", updated)
        self.assertNotIn("Voting is open.", updated)
        self.assertIn(rate.RATING_MARKER, updated)

    def test_own_reaction_and_bots_dont_vote(self) -> None:
        reactions = [{"user": {"login": "ann"}, "content": "+1", "created_at": "2026-10-17T00:00:00Z"},
                     {"user": {"login": "bob"}, "content": "+1", "created_at": "2026-10-17T00:00:00Z"},
                     {"user": {"login": "x[bot]"}, "content": "+1", "created_at": "2026-10-17T00:00:00Z"},
                     {"user": {"login": "cy"}, "content": "heart", "created_at": "2026-10-17T00:00:00Z"}]
        self.assertEqual([v.login for v in communitymerge.reactions_as_votes(reactions, "ann")], ["bob"])


class TriageTest(unittest.TestCase):
    def test_labels(self) -> None:
        self.assertEqual(triage.labels_for(["content/spells/forms/frost/frost.gd", "content/spells/forms/frost/icon.png"]),
                         {"area:spells", "code", "pixel-art"})
        self.assertEqual(triage.labels_for(["audio/music/theme.ogg"]), {"area:audio", "music"})
        self.assertEqual(triage.labels_for(["content/story/lore/a.json"]), {"area:story", "writing"})


class SubmissionsTest(unittest.TestCase):
    def test_parse_form(self) -> None:
        body = ("### Task\n\n#12\n\n### Where should it go?\n\n_No response_\n\n### File\n\n"
                "![x](https://github.com/user-attachments/assets/1234-abcd)\n\n### Agreement\n\n"
                "- [X] I have read the CLA and I agree to it (https://x)\n- [ ] I made this, or I have the right")
        f = submissions.parse_form(body)
        self.assertEqual(f["Task"], "#12")
        self.assertEqual(f["Where should it go?"], "")
        self.assertEqual(submissions.ATTACHMENT.findall(f["File"]), ["https://github.com/user-attachments/assets/1234-abcd"])
        self.assertTrue(submissions.checked(f["Agreement"], "I have read the CLA and I agree to it"))
        self.assertFalse(submissions.checked(f["Agreement"], "I made this, or I have the right to submit it"))

    def test_png_is_reencoded_without_extra_chunks(self) -> None:
        out, w, h = submissions.reencode_png(png(32, 32))
        self.assertEqual((w, h), (32, 32))
        self.assertNotIn(b"hidden payload", out)
        self.assertEqual(submissions.reencode_png(out)[0], out)  # stable

    def test_bad_pngs_are_refused(self) -> None:
        for bad in [b"GIF89a", png(32, 32, extra=b"MZ trailing exe"), png(32, 32)[:-8], png(5000, 1)]:
            with self.assertRaises(submissions.Invalid):
                submissions.reencode_png(bad)

    def test_target_path_validation(self) -> None:
        ok = submissions.target_path(None, "art", {"Where should it go?": "content/spells/forms/bolt/icon.png"})
        self.assertEqual(ok, "content/spells/forms/bolt/icon.png")
        for bad in ["ci/evil.png", "content/../ci/x.png", "content/spells/icon.ogg", ".github/x.png"]:
            with self.assertRaises(submissions.Invalid):
                submissions.target_path(None, "art", {"Where should it go?": bad})


class QuarantineTest(unittest.TestCase):
    def test_placeholder_keeps_size(self) -> None:
        data = quarantine.placeholder_png(48, 16)
        self.assertEqual(quarantine.png_size(data), (48, 16))
        submissions.reencode_png(data)  # a valid PNG

    def test_only_asset_and_manifests(self) -> None:
        title = "Quarantine content/enemies/slime/slime.png (copyright report #9)"
        self.assertTrue(quarantine.allowed_quarantine_change({"content/enemies/slime/slime.png", "art/manifest.json"}, title))
        self.assertFalse(quarantine.allowed_quarantine_change({"content/enemies/slime/slime.png", "core/x.gd"}, title))
        self.assertFalse(quarantine.allowed_quarantine_change({"art/manifest.json"}, "Something else"))


class ClaimsAndClaTest(unittest.TestCase):
    def test_claim_and_signing_comments(self) -> None:
        self.assertTrue(claims.is_claim("/claim"))
        self.assertTrue(claims.is_claim("  /Claim please"))
        self.assertFalse(claims.is_claim("I'd like to /claim this"))
        self.assertTrue(cla.is_signing_comment("I have read the CLA and I agree to it."))
        self.assertFalse(cla.is_signing_comment("I have not read the CLA and I agree to it."))

    def test_add_signatures_dedupes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp, "sig.json")
            sig = cla.Signature(5, "ann", "1.0", "2026-10-17T00:00:00Z", "https://x")
            self.assertEqual(cla.add_signatures(path, [sig, sig], "1.0"), 1)
            self.assertEqual(cla.add_signatures(path, [sig], "1.0"), 0)
            data = json.loads(path.read_text())
            self.assertTrue(cla.has_signed(data["signatures"], 5, "1.0"))
            self.assertFalse(cla.has_signed(data["signatures"], 5, "2.0"))


if __name__ == "__main__":
    unittest.main()
