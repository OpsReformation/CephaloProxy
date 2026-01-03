"""
Unit tests for init-squid.py initialization script.

Tests cover:
- squid.conf parsing for cache_dir detection
- Missing volume detection and error messages
- Cache initialization subprocess calls
- SSL database initialization
- Permission validation

Requirements:
- 90%+ code coverage
- All edge cases from spec.md tested
- Mock subprocess calls and filesystem operations
"""

import os
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock, MagicMock, patch, mock_open, call

# Add container directory to path to import init-squid module
sys.path.insert(0, str(Path(__file__).parent.parent.parent / 'container'))

# Import the module under test (rename to avoid dash in module name)
import importlib.util
spec = importlib.util.spec_from_file_location(
    "init_squid",
    Path(__file__).parent.parent.parent / "container" / "init-squid.py"
)
init_squid = importlib.util.module_from_spec(spec)
spec.loader.exec_module(init_squid)


class TestCacheDirParsing(unittest.TestCase):
    """Test squid.conf parsing for cache_dir directive."""

    def test_parse_cache_dir_found(self):
        """Test parsing cache_dir directive from config."""
        config_content = """
# Squid configuration
cache_dir ufs /var/spool/squid 1000 16 256
http_port 3128
"""
        with patch('builtins.open', mock_open(read_data=config_content)):
            with patch.object(init_squid.SQUID_CONF, 'exists', return_value=True):
                result = init_squid.parse_cache_dir_from_config()
                self.assertEqual(result, Path("/var/spool/squid"))

    def test_parse_cache_dir_custom_path(self):
        """Test parsing custom cache_dir path."""
        config_content = """
cache_dir ufs /custom/cache/path 5000 32 512
"""
        with patch('builtins.open', mock_open(read_data=config_content)):
            with patch.object(init_squid.SQUID_CONF, 'exists', return_value=True):
                result = init_squid.parse_cache_dir_from_config()
                self.assertEqual(result, Path("/custom/cache/path"))

    def test_parse_cache_dir_commented_out(self):
        """Test that commented cache_dir directive is ignored."""
        config_content = """
# cache_dir ufs /var/spool/squid 1000 16 256
http_port 3128
"""
        with patch('builtins.open', mock_open(read_data=config_content)):
            with patch.object(init_squid.SQUID_CONF, 'exists', return_value=True):
                result = init_squid.parse_cache_dir_from_config()
                self.assertIsNone(result)

    def test_parse_cache_dir_missing_config(self):
        """Test behavior when squid.conf doesn't exist."""
        with patch.object(init_squid.SQUID_CONF, 'exists', return_value=False):
            result = init_squid.parse_cache_dir_from_config()
            self.assertIsNone(result)

    def test_parse_cache_dir_multiple_directives(self):
        """Test that first cache_dir directive is used."""
        config_content = """
cache_dir ufs /first/cache 1000 16 256
cache_dir ufs /second/cache 2000 16 256
"""
        with patch('builtins.open', mock_open(read_data=config_content)):
            with patch.object(init_squid.SQUID_CONF, 'exists', return_value=True):
                result = init_squid.parse_cache_dir_from_config()
                self.assertEqual(result, Path("/first/cache"))


class TestSSLBumpDetection(unittest.TestCase):
    """Test SSL-bump detection from squid.conf."""

    def test_ssl_bump_enabled_sslcrtd_program(self):
        """Test detection of sslcrtd_program directive."""
        config_content = """
sslcrtd_program /usr/libexec/squid/security_file_certgen -s /var/lib/squid/ssl_db -M 4MB
"""
        with patch('builtins.open', mock_open(read_data=config_content)):
            with patch.object(init_squid.SQUID_CONF, 'exists', return_value=True):
                result = init_squid.check_ssl_bump_enabled()
                self.assertTrue(result)

    def test_ssl_bump_disabled(self):
        """Test when SSL-bump is not configured."""
        config_content = """
http_port 3128
cache_dir ufs /var/spool/squid 1000 16 256
"""
        with patch('builtins.open', mock_open(read_data=config_content)):
            with patch.object(init_squid.SQUID_CONF, 'exists', return_value=True):
                result = init_squid.check_ssl_bump_enabled()
                self.assertFalse(result)

    def test_ssl_bump_commented_out(self):
        """Test that commented SSL directives are ignored."""
        config_content = """
# sslcrtd_program /usr/libexec/squid/security_file_certgen -s /var/lib/squid/ssl_db -M 4MB
http_port 3128
"""
        with patch('builtins.open', mock_open(read_data=config_content)):
            with patch.object(init_squid.SQUID_CONF, 'exists', return_value=True):
                result = init_squid.check_ssl_bump_enabled()
                self.assertFalse(result)


class TestCacheSizeParsing(unittest.TestCase):
    """Test cache size extraction from squid.conf."""

    def test_get_cache_size_found(self):
        """Test extracting cache size from config."""
        config_content = """
cache_dir ufs /var/spool/squid 5000 32 512
"""
        with patch('builtins.open', mock_open(read_data=config_content)):
            with patch.object(init_squid.SQUID_CONF, 'exists', return_value=True):
                result = init_squid.get_cache_size_from_config()
                self.assertEqual(result, 5000)

    def test_get_cache_size_not_found(self):
        """Test when no cache_dir directive present."""
        config_content = """
http_port 3128
"""
        with patch('builtins.open', mock_open(read_data=config_content)):
            with patch.object(init_squid.SQUID_CONF, 'exists', return_value=True):
                result = init_squid.get_cache_size_from_config()
                self.assertIsNone(result)


class TestVolumeValidation(unittest.TestCase):
    """Test volume mount validation and error handling."""

    @patch('os.access')
    @patch.object(Path, 'exists')
    def test_volume_writable_success(self, mock_exists, mock_access):
        """Test successful volume validation."""
        mock_exists.return_value = True
        mock_access.return_value = True

        result = init_squid.validate_volume_writable(
            Path("/test/path"),
            "Test Volume",
            required=True
        )
        self.assertTrue(result)

    @patch.object(Path, 'exists')
    def test_volume_missing_required_fails(self, mock_exists):
        """Test that missing required volume causes exit (FR-005)."""
        mock_exists.return_value = False

        with self.assertRaises(SystemExit) as cm:
            init_squid.validate_volume_writable(
                Path("/missing/path"),
                "Cache",
                required=True
            )
        self.assertEqual(cm.exception.code, 1)

    @patch.object(Path, 'exists')
    def test_volume_missing_optional_warns(self, mock_exists):
        """Test that missing optional volume returns False but doesn't exit."""
        mock_exists.return_value = False

        result = init_squid.validate_volume_writable(
            Path("/missing/path"),
            "Optional Volume",
            required=False
        )
        self.assertFalse(result)

    @patch('os.access')
    @patch.object(Path, 'exists')
    def test_volume_not_writable_required_fails(self, mock_exists, mock_access):
        """Test that non-writable required volume causes exit."""
        mock_exists.return_value = True
        mock_access.return_value = False

        with self.assertRaises(SystemExit) as cm:
            init_squid.validate_volume_writable(
                Path("/readonly/path"),
                "Cache",
                required=True
            )
        self.assertEqual(cm.exception.code, 1)

    @patch('os.access')
    @patch.object(Path, 'exists')
    def test_volume_not_writable_optional_warns(self, mock_exists, mock_access):
        """Test that non-writable optional volume returns False."""
        mock_exists.return_value = True
        mock_access.return_value = False

        result = init_squid.validate_volume_writable(
            Path("/readonly/path"),
            "Log",
            required=False
        )
        self.assertFalse(result)


class TestCacheInitialization(unittest.TestCase):
    """Test cache directory initialization."""

    @patch('subprocess.run')
    @patch.object(Path, 'exists')
    def test_cache_already_initialized(self, mock_exists, mock_subprocess):
        """Test that already initialized cache is skipped."""
        # Cache directory 00 exists - already initialized
        mock_exists.return_value = True

        init_squid.initialize_cache_directory(Path("/var/spool/squid"))

        # subprocess should not be called
        mock_subprocess.assert_not_called()

    @patch('subprocess.run')
    @patch.object(Path, 'exists')
    def test_cache_initialization_success(self, mock_exists, mock_subprocess):
        """Test successful cache initialization."""
        # Cache not initialized yet
        mock_exists.return_value = False

        # Mock successful squid -z
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = ""
        mock_result.stderr = ""
        mock_subprocess.return_value = mock_result

        init_squid.initialize_cache_directory(Path("/var/spool/squid"))

        # Verify squid -z was called
        mock_subprocess.assert_called_once()
        call_args = mock_subprocess.call_args
        self.assertEqual(call_args[0][0][0], "squid")
        self.assertEqual(call_args[0][0][1], "-z")

    @patch('subprocess.run')
    @patch.object(Path, 'exists')
    def test_cache_initialization_failure(self, mock_exists, mock_subprocess):
        """Test cache initialization failure causes exit."""
        mock_exists.return_value = False

        # Mock failed squid -z
        mock_result = Mock()
        mock_result.returncode = 1
        mock_result.stdout = ""
        mock_result.stderr = "Error: Permission denied"
        mock_subprocess.return_value = mock_result

        with self.assertRaises(SystemExit) as cm:
            init_squid.initialize_cache_directory(Path("/var/spool/squid"))
        self.assertEqual(cm.exception.code, 1)

    @patch('subprocess.run')
    @patch.object(Path, 'exists')
    def test_cache_initialization_squid_not_found(self, mock_exists, mock_subprocess):
        """Test that missing squid binary causes exit."""
        mock_exists.return_value = False
        mock_subprocess.side_effect = FileNotFoundError("squid not found")

        with self.assertRaises(SystemExit) as cm:
            init_squid.initialize_cache_directory(Path("/var/spool/squid"))
        self.assertEqual(cm.exception.code, 1)


class TestSSLDatabaseInitialization(unittest.TestCase):
    """Test SSL certificate database initialization."""

    @patch.object(Path, 'exists')
    def test_ssl_db_already_initialized(self, mock_exists):
        """Test that already initialized SSL DB is skipped."""
        # Mock /var/lib/squid/ssl_db/certs exists
        def exists_side_effect(path):
            if 'certs' in str(path):
                return True
            return False

        with patch.object(Path, 'exists', side_effect=exists_side_effect):
            with patch('subprocess.run') as mock_subprocess:
                init_squid.initialize_ssl_database(Path("/var/lib/squid/ssl_db"))
                mock_subprocess.assert_not_called()

    @patch('subprocess.run')
    @patch('shutil.rmtree')
    @patch.object(Path, 'exists')
    @patch.object(Path, 'rmdir')
    def test_ssl_db_initialization_success(self, mock_rmdir, mock_exists, mock_rmtree, mock_subprocess):
        """Test successful SSL database initialization."""
        # Mock directory doesn't exist initially, then exists after creation
        call_count = [0]

        def exists_side_effect(path=None):
            call_count[0] += 1
            # certs dir doesn't exist, parent dir exists, certgen exists
            if 'certs' in str(path):
                return False
            if 'security_file_certgen' in str(path):
                return True
            if call_count[0] > 5:  # After creation
                return True
            return False

        mock_exists.side_effect = exists_side_effect

        # Mock successful security_file_certgen
        mock_result = Mock()
        mock_result.returncode = 0
        mock_result.stdout = ""
        mock_result.stderr = ""
        mock_subprocess.return_value = mock_result

        # Mock os.walk for permission setting
        with patch('os.walk', return_value=[]):
            init_squid.initialize_ssl_database(Path("/var/lib/squid/ssl_db"))

        # Verify security_file_certgen was called
        mock_subprocess.assert_called_once()
        call_args = mock_subprocess.call_args[0][0]
        self.assertIn("security_file_certgen", call_args[0])
        self.assertIn("-c", call_args)
        self.assertIn("-s", call_args)

    @patch('subprocess.run')
    @patch.object(Path, 'exists')
    def test_ssl_db_initialization_certgen_not_found(self, mock_exists, mock_subprocess):
        """Test that missing security_file_certgen causes exit."""
        def exists_side_effect(path=None):
            if 'certs' in str(path):
                return False
            if 'security_file_certgen' in str(path):
                return False  # Certgen not found
            return True

        mock_exists.side_effect = exists_side_effect

        with self.assertRaises(SystemExit) as cm:
            init_squid.initialize_ssl_database(Path("/var/lib/squid/ssl_db"))
        self.assertEqual(cm.exception.code, 1)

    @patch('subprocess.run')
    @patch.object(Path, 'exists')
    def test_ssl_db_initialization_failure(self, mock_exists, mock_subprocess):
        """Test SSL database initialization failure causes exit."""
        def exists_side_effect(path=None):
            if 'certs' in str(path):
                return False
            if 'security_file_certgen' in str(path):
                return True
            return True

        mock_exists.side_effect = exists_side_effect

        # Mock failed security_file_certgen
        mock_result = Mock()
        mock_result.returncode = 1
        mock_result.stdout = ""
        mock_result.stderr = "Error: Permission denied"
        mock_subprocess.return_value = mock_result

        with patch.object(Path, 'stat'):
            with self.assertRaises(SystemExit) as cm:
                init_squid.initialize_ssl_database(Path("/var/lib/squid/ssl_db"))
            self.assertEqual(cm.exception.code, 1)


class TestCacheSizeValidation(unittest.TestCase):
    """Test cache size validation logic."""

    @patch('shutil.disk_usage')
    @patch('init_squid.get_cache_size_from_config')
    def test_cache_size_overfill_warning(self, mock_get_size, mock_disk_usage):
        """Test warning when configured size exceeds available space."""
        mock_get_size.return_value = 10000  # 10GB configured

        # Mock disk: 8GB total
        mock_stat = Mock()
        mock_stat.total = 8 * 1024 * 1024 * 1024
        mock_disk_usage.return_value = mock_stat

        with self.assertLogs(level='WARNING') as cm:
            init_squid.validate_cache_size(Path("/var/spool/squid"))

        # Should warn about size mismatch
        self.assertTrue(any("mismatch" in msg.lower() for msg in cm.output))

    @patch('shutil.disk_usage')
    @patch('init_squid.get_cache_size_from_config')
    def test_cache_size_underutilization_warning(self, mock_get_size, mock_disk_usage):
        """Test warning when cache is significantly underutilized."""
        mock_get_size.return_value = 1000  # 1GB configured

        # Mock disk: 100GB total
        mock_stat = Mock()
        mock_stat.total = 100 * 1024 * 1024 * 1024
        mock_disk_usage.return_value = mock_stat

        with self.assertLogs(level='WARNING') as cm:
            init_squid.validate_cache_size(Path("/var/spool/squid"))

        # Should warn about underutilization
        self.assertTrue(any("underutilization" in msg.lower() for msg in cm.output))

    @patch('shutil.disk_usage')
    @patch('init_squid.get_cache_size_from_config')
    def test_cache_size_optimal(self, mock_get_size, mock_disk_usage):
        """Test no warning when cache size is optimal."""
        mock_get_size.return_value = 8000  # 8GB configured

        # Mock disk: 10GB total
        mock_stat = Mock()
        mock_stat.total = 10 * 1024 * 1024 * 1024
        mock_disk_usage.return_value = mock_stat

        # Should log info, not warning
        with self.assertLogs(level='INFO'):
            init_squid.validate_cache_size(Path("/var/spool/squid"))

    @patch('init_squid.get_cache_size_from_config')
    def test_cache_size_not_configured(self, mock_get_size):
        """Test graceful handling when cache size not in config."""
        mock_get_size.return_value = None

        # Should not raise exception
        init_squid.validate_cache_size(Path("/var/spool/squid"))


class TestMainFlow(unittest.TestCase):
    """Test main initialization flow and edge cases."""

    @patch('init_squid.validate_volume_writable')
    @patch('init_squid.check_ssl_bump_enabled')
    @patch('init_squid.validate_cache_size')
    @patch('init_squid.initialize_cache_directory')
    @patch('init_squid.parse_cache_dir_from_config')
    def test_main_with_cache_dir(self, mock_parse, mock_init_cache, mock_validate_size,
                                   mock_ssl_check, mock_validate_vol):
        """Test main flow with cache_dir configured."""
        mock_parse.return_value = Path("/var/spool/squid")
        mock_ssl_check.return_value = False
        mock_validate_vol.return_value = True

        result = init_squid.main()

        self.assertEqual(result, 0)
        mock_validate_vol.assert_called()
        mock_init_cache.assert_called_once()
        mock_validate_size.assert_called_once()

    @patch('init_squid.validate_volume_writable')
    @patch('init_squid.initialize_ssl_database')
    @patch('init_squid.check_ssl_bump_enabled')
    @patch('init_squid.parse_cache_dir_from_config')
    def test_main_with_ssl_bump(self, mock_parse, mock_ssl_check, mock_init_ssl, mock_validate_vol):
        """Test main flow with SSL-bump enabled."""
        mock_parse.return_value = Path("/var/spool/squid")
        mock_ssl_check.return_value = True
        mock_validate_vol.return_value = True

        with patch('init_squid.initialize_cache_directory'):
            with patch('init_squid.validate_cache_size'):
                result = init_squid.main()

        self.assertEqual(result, 0)
        mock_init_ssl.assert_called_once()

    @patch('init_squid.check_ssl_bump_enabled')
    @patch('init_squid.parse_cache_dir_from_config')
    def test_main_no_cache_dir_configured(self, mock_parse, mock_ssl_check):
        """Test main flow when no cache_dir directive in config."""
        mock_parse.return_value = None
        mock_ssl_check.return_value = False

        with patch.object(init_squid.DEFAULT_CACHE_DIR, 'exists', return_value=False):
            with patch('init_squid.validate_volume_writable') as mock_validate:
                mock_validate.return_value = False
                result = init_squid.main()

        self.assertEqual(result, 0)


if __name__ == '__main__':
    unittest.main()
