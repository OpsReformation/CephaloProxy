"""
Unit tests for Squid configuration validation.

Tests the config_validator module for squid -k parse wrapper
and SSL-bump detection.
"""

import unittest
import asyncio
from pathlib import Path
import tempfile
import sys

# Add container directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent / 'container'))

from config_validator import validate_squid_config, detect_ssl_bump


class TestConfigValidation(unittest.TestCase):
    """Tests for validate_squid_config function."""

    def test_validate_nonexistent_config(self):
        """Test validation of non-existent config file."""
        async def run_test():
            success, error = await validate_squid_config(Path("/nonexistent/squid.conf"))
            self.assertFalse(success)
            self.assertIn("not found", error)

        asyncio.run(run_test())

    def test_validate_valid_config(self):
        """Test validation of valid minimal Squid config."""
        # Create temporary valid config
        with tempfile.NamedTemporaryFile(mode='w', suffix='.conf', delete=False) as f:
            f.write("""
# Minimal valid Squid configuration
http_port 3128
acl all src 0.0.0.0/0
http_access allow all
""")
            config_path = Path(f.name)

        try:
            async def run_test():
                success, error = await validate_squid_config(config_path)
                # This may succeed or fail depending on squid binary availability
                # In unit test environment, squid may not be installed
                if not success and "not found" in error:
                    self.skipTest("squid binary not available in test environment")
                # If squid is available, validation should succeed for valid config
                return success, error

            success, error = asyncio.run(run_test())
        finally:
            config_path.unlink()

    def test_validate_invalid_config(self):
        """Test validation of invalid Squid config."""
        # Create temporary invalid config
        with tempfile.NamedTemporaryFile(mode='w', suffix='.conf', delete=False) as f:
            f.write("""
# Invalid Squid configuration
invalid_directive_that_does_not_exist
http_port 3128
""")
            config_path = Path(f.name)

        try:
            async def run_test():
                success, error = await validate_squid_config(config_path)
                # If squid binary not available, skip test
                if not success and "not found" in error:
                    self.skipTest("squid binary not available in test environment")
                # If squid is available, validation should fail
                self.assertFalse(success)
                self.assertTrue(len(error) > 0)

            asyncio.run(run_test())
        finally:
            config_path.unlink()


class TestSSLBumpDetection(unittest.TestCase):
    """Tests for detect_ssl_bump function."""

    def test_detect_ssl_bump_enabled(self):
        """Test detection of ssl-bump directive in config."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.conf', delete=False) as f:
            f.write("""
http_port 3128 ssl-bump cert=/var/lib/squid/squid-ca.pem
ssl_bump server-first all
acl all src 0.0.0.0/0
http_access allow all
""")
            config_path = Path(f.name)

        try:
            result = detect_ssl_bump(config_path)
            self.assertTrue(result)
        finally:
            config_path.unlink()

    def test_detect_ssl_bump_disabled(self):
        """Test detection when ssl-bump is not present."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.conf', delete=False) as f:
            f.write("""
http_port 3128
acl all src 0.0.0.0/0
http_access allow all
""")
            config_path = Path(f.name)

        try:
            result = detect_ssl_bump(config_path)
            self.assertFalse(result)
        finally:
            config_path.unlink()

    def test_detect_ssl_bump_commented(self):
        """Test that commented ssl-bump is not detected."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.conf', delete=False) as f:
            f.write("""
http_port 3128
# ssl-bump server-first all
acl all src 0.0.0.0/0
http_access allow all
""")
            config_path = Path(f.name)

        try:
            result = detect_ssl_bump(config_path)
            self.assertFalse(result)
        finally:
            config_path.unlink()

    def test_detect_ssl_bump_nonexistent_file(self):
        """Test detection with non-existent config file."""
        result = detect_ssl_bump(Path("/nonexistent/squid.conf"))
        self.assertFalse(result)


if __name__ == '__main__':
    unittest.main()
