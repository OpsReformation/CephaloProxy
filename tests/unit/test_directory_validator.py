"""
Unit tests for directory permission validation.

Tests the directory_validator module for directory writability checks.
"""

import unittest
import tempfile
import os
from pathlib import Path
import sys

# Add container directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent / 'container'))

from directory_validator import check_directory_writable, validate_directories


class TestDirectoryWritable(unittest.TestCase):
    """Tests for check_directory_writable function."""

    def test_writable_directory(self):
        """Test that writable directory is detected as writable."""
        with tempfile.TemporaryDirectory() as tmpdir:
            self.assertTrue(check_directory_writable(Path(tmpdir)))

    def test_nonexistent_directory(self):
        """Test that non-existent directory returns False."""
        self.assertFalse(check_directory_writable(Path("/nonexistent/directory")))

    def test_readonly_directory(self):
        """Test that read-only directory is detected as not writable."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)

            # Create a subdirectory and make it read-only
            readonly_dir = tmpdir_path / "readonly"
            readonly_dir.mkdir()

            # Remove write permissions
            os.chmod(readonly_dir, 0o555)

            try:
                self.assertFalse(check_directory_writable(readonly_dir))
            finally:
                # Restore permissions for cleanup
                os.chmod(readonly_dir, 0o755)


class TestValidateDirectories(unittest.TestCase):
    """Tests for validate_directories function."""

    def test_validate_directories_structure(self):
        """Test that validate_directories returns correct structure."""
        errors = validate_directories()

        # Should return a list
        self.assertIsInstance(errors, list)

        # Each error should be a tuple of (Path, str)
        for error in errors:
            self.assertIsInstance(error, tuple)
            self.assertEqual(len(error), 2)
            self.assertIsInstance(error[0], Path)
            self.assertIsInstance(error[1], str)

    def test_validate_directories_error_messages(self):
        """Test that error messages contain UID/GID information."""
        # In test environment, /var/run/squid likely doesn't exist
        # This will generate errors with UID/GID info
        errors = validate_directories()

        if errors:
            # Check that error messages contain UID/GID
            for path, message in errors:
                self.assertIn("UID:", message)
                self.assertIn("GID:", message)


if __name__ == '__main__':
    unittest.main()
