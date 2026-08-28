#!/usr/bin/env python3
import unittest
import sys
import os

# Add scripts directory to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "scripts")))
import status

class TestStatusScript(unittest.TestCase):
    def test_parse_size(self):
        self.assertEqual(status.parse_size(0), "0 B")
        self.assertEqual(status.parse_size(1024), "1.0 KB")
        self.assertEqual(status.parse_size(1048576), "1.0 MB")
        self.assertEqual(status.parse_size(1073741824), "1.0 GB")
        self.assertEqual(status.parse_size(1099511627776), "1.0 TB")
        self.assertEqual(status.parse_size(None), "N/A")
        self.assertEqual(status.parse_size("invalid"), "N/A")

    def test_compute_speeds_delta(self):
        orig_io, orig_time = status.read_proc_io, status.time.time
        cur = {"v": None}
        try:
            status.read_proc_io = lambda pid: cur["v"][0]
            status.time.time = lambda: cur["v"][1]
            try:
                os.remove(status._io_state_path())
            except OSError:
                pass
            # first poll: no prior sample -> speed unknown
            cur["v"] = ({"rchar": 0, "wchar": 0}, 100.0)
            procs = status.compute_speeds([{"pid": 424242}])
            self.assertEqual(procs[0]["speed_bps"], 0)
            self.assertEqual(procs[0]["speed_formatted"], "—")
            # second poll: +8000 bytes over 2s, halved for read+write => 2000 B/s
            cur["v"] = ({"rchar": 4000, "wchar": 4000}, 102.0)
            procs = status.compute_speeds([{"pid": 424242}])
            self.assertEqual(procs[0]["speed_bps"], 2000)
            self.assertTrue(procs[0]["speed_formatted"].endswith("/s"))
        finally:
            status.read_proc_io, status.time.time = orig_io, orig_time
            try:
                os.remove(status._io_state_path())
            except OSError:
                pass

    def test_compute_speeds_no_io(self):
        orig_io = status.read_proc_io
        try:
            status.read_proc_io = lambda pid: None
            procs = status.compute_speeds([{"pid": 1}])
            self.assertEqual(procs[0]["speed_bps"], 0)
        finally:
            status.read_proc_io = orig_io

    def test_quota_ttl_seconds(self):
        orig_argv, orig_env = status.sys.argv, dict(os.environ)
        try:
            status.sys.argv = ["status.py", "--quota-ttl", "300"]
            self.assertEqual(status.quota_ttl_seconds(), 300)
            status.sys.argv = ["status.py", "--quota-ttl", "0"]
            self.assertEqual(status.quota_ttl_seconds(), 0)
            status.sys.argv = ["status.py"]
            os.environ.pop("RCLONE_PANEL_QUOTA_TTL", None)
            self.assertEqual(status.quota_ttl_seconds(default=42), 42)
            os.environ["RCLONE_PANEL_QUOTA_TTL"] = "77"
            self.assertEqual(status.quota_ttl_seconds(), 77)
        finally:
            status.sys.argv = orig_argv
            os.environ.clear()
            os.environ.update(orig_env)

    def test_get_configured_remotes_uses_cache(self):
        orig_run, orig_which = status.safe_run, status.shutil.which
        calls = {"about": 0}

        def fake_run(cmd, timeout=5):
            if cmd[:2] == ["rclone", "listremotes"]:
                return "gdrive: drive"
            if cmd[:2] == ["rclone", "about"]:
                calls["about"] += 1
                return '{"total": 1000, "used": 400, "free": 600}'
            return ""

        try:
            os.remove(status._quota_cache_path())
        except OSError:
            pass
        try:
            status.shutil.which = lambda _b: "/usr/bin/rclone"
            status.safe_run = fake_run
            first = status.get_configured_remotes(quota_ttl=900)
            second = status.get_configured_remotes(quota_ttl=900)   # served from cache
            forced = status.get_configured_remotes(quota_ttl=0)     # bypasses cache
            self.assertEqual(calls["about"], 2)
            self.assertTrue(first[0]["has_quota"])
            self.assertTrue(second[0]["has_quota"])
            self.assertEqual(second[0]["used_bytes"], 400)
            self.assertTrue(forced[0]["has_quota"])
        finally:
            status.safe_run, status.shutil.which = orig_run, orig_which
            try:
                os.remove(status._quota_cache_path())
            except OSError:
                pass

    def test_sanitize_usec(self):
        self.assertEqual(status.sanitize_usec(0), 0)
        self.assertEqual(status.sanitize_usec(None), 0)
        self.assertEqual(status.sanitize_usec("nope"), 0)
        self.assertEqual(status.sanitize_usec(2 ** 64 - 1), 0)
        self.assertEqual(status.sanitize_usec(2 ** 63 - 1), 0)
        self.assertEqual(status.sanitize_usec(1723000000000000), 1723000000000000)

    def test_format_relative_time(self):
        now_s = 1000000.0
        # 10 minutes in future
        future_us = int((now_s + 600) * 1000000)
        self.assertEqual(status.format_relative_time(future_us, now_s), "in 10m")
        
        # 2 hours in past
        past_us = int((now_s - 7200) * 1000000)
        self.assertEqual(status.format_relative_time(past_us, now_s), "2h 0m ago")

    def test_rclone_detection(self):
        # Basic sanity check on system
        remotes = status.get_configured_remotes()
        self.assertIsInstance(remotes, list)

        mounts = status.get_fuse_mounts()
        self.assertIsInstance(mounts, list)

        timers = status.get_scheduled_timers()
        self.assertIsInstance(timers, list)

if __name__ == "__main__":
    unittest.main()
