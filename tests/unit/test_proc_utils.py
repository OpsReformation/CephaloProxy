"""
Unit tests for /proc filesystem parsing utilities.

Tests the proc_utils module functions for process existence checking
and /proc/[pid]/status parsing.
"""

import os
import unittest
from pathlib import Path
import sys

# Add container directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent / 'container'))

from proc_utils import check_process_running, parse_proc_status


class TestProcessRunningCheck(unittest.TestCase):
    """Tests for check_process_running function."""

    def test_check_process_running_self(self):
        """Test that current Python process is detected as running."""
        self_pid = os.getpid()
        self.assertTrue(check_process_running(self_pid))

    def test_check_process_running_nonexistent(self):
        """Test that non-existent PID returns False."""
        # Use a very high PID that's unlikely to exist
        self.assertFalse(check_process_running(999999))

    def test_check_process_running_pid_1(self):
        """Test that PID 1 (init/systemd) is running."""
        # PID 1 should always exist on Linux
        self.assertTrue(check_process_running(1))


class TestProcStatusParsing(unittest.TestCase):
    """Tests for parse_proc_status function."""

    def test_parse_proc_status_self(self):
        """Test parsing /proc/self/status."""
        self_pid = os.getpid()
        info = parse_proc_status(self_pid)

        self.assertIsNotNone(info)
        self.assertIn('Name', info)
        self.assertIn('Pid', info)
        self.assertIn('State', info)

        # Verify PID matches
        self.assertEqual(int(info['Pid']), self_pid)

        # Verify state is valid (R=running, S=sleeping, etc.)
        self.assertIn(info['State'][0], ['R', 'S', 'D', 'Z', 'T'])

    def test_parse_proc_status_nonexistent(self):
        """Test parsing non-existent PID returns None."""
        info = parse_proc_status(999999)
        self.assertIsNone(info)

    def test_parse_proc_status_pid_1(self):
        """Test parsing PID 1 (init/systemd) status."""
        info = parse_proc_status(1)

        self.assertIsNotNone(info)
        self.assertIn('Name', info)
        self.assertIn('Pid', info)

        # Verify PID is 1
        self.assertEqual(int(info['Pid']), 1)


if __name__ == '__main__':
    unittest.main()
