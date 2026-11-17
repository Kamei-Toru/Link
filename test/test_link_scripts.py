# Version: 1.2b
"""Run with: python3 -m unittest discover -s test -v (requires zsh)."""
from datetime import datetime
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ScriptsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.home = self.root / 'home'
        self.source = self.root / 'source'
        self.dest = self.root / 'dest'
        self.home.mkdir()
        self.source.mkdir()
        self.config = self.root / 'config'
        self.config.write_text(f'shell|{self.dest}|sh,zsh\npython|{self.root}/python|py\n')
        self.env = dict(os.environ, HOME=str(self.home))

    def run_script(self, script, *args, expected=0):
        result = subprocess.run(['zsh', str(ROOT / script), *map(str, args)],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def slnk(self, *args, expected=0):
        return self.run_script('slnk.zsh', '-c', self.config, *args, expected=expected)

    def write(self, relative, content='source'):
        file = self.source / relative
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content)
        return file

    def fail_command(self, name):
        bin_dir = self.root / 'bin'
        bin_dir.mkdir(exist_ok=True)
        wrapper = bin_dir / name
        wrapper.write_text('#!/bin/sh\nexit 73\n')
        wrapper.chmod(0o755)
        self.env['PATH'] = str(bin_dir) + os.pathsep + os.environ['PATH']

    def test_help(self):
        for script in ['link.zsh', 'slnk.zsh', 'link_install.zsh']:
            for option in ['-h', '--help']:
                self.run_script(script, option)

    def test_language_and_missing_source_continuation(self):
        self.config.write_text(f'ruby|{self.dest}|rb\npython|{self.root}/python|py\n')
        original = self.write('hello.RB')
        self.slnk(self.root / 'missing', self.source, expected=1)
        self.assertEqual((self.dest / 'hello.RB').resolve(), original)
        self.assertTrue((self.root / 'python').is_dir())

    def test_config_rejects_empty_duplicate_and_unsafe_fields(self):
        for text in ['shell|/tmp/x|sh,', 'shell|/tmp/x|,sh',
                     'shell|/tmp/x|sh,,py', 'shell|/tmp/x|sh, ,py',
                     'shell|/tmp/x|sh\nother|/tmp/y|sh',
                     '|/tmp/x|sh', 'shell||sh', 'shell|/tmp/x|',
                     'shell|$(touch bad)|sh', 'shell|/tmp/x|sh|extra']:
            with self.subTest(text=text):
                self.config.write_text(text)
                self.slnk(self.source, expected=2)
                self.assertFalse(self.dest.exists())

    def test_same_link_skip_and_directory_link_replacement(self):
        original = self.write('job.sh')
        self.slnk(self.source)
        self.assertIn('1 skipped', self.slnk(self.source).stdout)
        target = self.dest / 'job.sh'
        target.unlink()
        target.symlink_to(self.home, target_is_directory=True)
        self.slnk(self.source)
        self.assertEqual(target.resolve(), original)
        self.assertFalse((self.home / 'link').exists())
        self.assertFalse(list(self.dest.glob('.link-stage.*')))

    def test_link_creation_failure_preserves_existing_link(self):
        self.write('job.sh')
        self.dest.mkdir()
        target = self.dest / 'job.sh'
        target.symlink_to(self.home)
        self.fail_command('ln')
        self.slnk(self.source, expected=1)
        self.assertEqual(target.resolve(), self.home)
        self.assertFalse(list(self.dest.glob('.link-stage.*')))

    def test_rename_failure_preserves_existing_link(self):
        self.write('job.sh')
        self.dest.mkdir()
        target = self.dest / 'job.sh'
        target.symlink_to(self.home)
        self.fail_command('mv')
        self.slnk(self.source, expected=1)
        self.assertEqual(target.resolve(), self.home)

    def test_backup_restore_on_link_failure(self):
        self.write('job.sh')
        self.dest.mkdir()
        target = self.dest / 'job.sh'
        target.write_text('original user file')
        self.fail_command('ln')
        self.slnk(self.source, expected=1)
        self.assertFalse(target.is_symlink())
        self.assertEqual(target.read_text(), 'original user file')
        self.assertFalse(list(self.dest.glob('job.sh.????????*')))

    def test_backup_sequence_preserves_existing_backup(self):
        self.write('job.sh')
        self.dest.mkdir()
        target = self.dest / 'job.sh'
        date = datetime.now().strftime('%Y%m%d')
        backup = Path(str(target) + '.' + date)
        backup.write_text('previous backup')
        for number in [1, 2]:
            if target.is_symlink():
                target.unlink()
            target.write_text(f'original {number}')
            self.slnk(self.source)
            self.assertEqual(Path(str(backup) + f'.{number}').read_text(), f'original {number}')
        self.assertEqual(backup.read_text(), 'previous backup')

    def test_source_collision_first_wins(self):
        first = self.write('job.sh')
        other = self.root / 'other'
        other.mkdir()
        (other / 'job.sh').write_text('other')
        self.slnk(self.source, other, expected=1)
        self.assertEqual((self.dest / 'job.sh').resolve(), first)

    def test_hidden_nested_and_source_symlinks_excluded(self):
        self.write('.hidden.sh')
        self.write('nested/skip.sh')
        self.write('visible.sh')
        (self.source / 'alias.sh').symlink_to(self.source / 'visible.sh')
        self.slnk(self.source)
        self.assertEqual([p.name for p in self.dest.iterdir()], ['visible.sh'])

    def test_link_tree_and_unusual_names(self):
        for name in ['a/README', 'b/README', 'space dir/line\nbreak', 'x/[literal]*']:
            self.write(name)
        self.write('.git/HEAD')
        self.run_script('link.zsh', self.source, self.dest)
        for name in ['a/README', 'b/README', 'space dir/line\nbreak', 'x/[literal]*']:
            self.assertEqual((self.dest / name).resolve(), self.source / name)
        self.assertFalse((self.dest / '.git').exists())

    def test_link_replacement_failure_preserves_link(self):
        self.write('file')
        self.dest.mkdir()
        target = self.dest / 'file'
        target.symlink_to(self.home)
        self.fail_command('ln')
        self.run_script('link.zsh', self.source, self.dest, expected=1)
        self.assertEqual(target.resolve(), self.home)

    def test_link_parent_symlink_is_rejected(self):
        self.write('sub/file')
        self.dest.mkdir()
        (self.dest / 'sub').symlink_to(self.home)
        self.run_script('link.zsh', self.source, self.dest, expected=1)
        self.assertFalse((self.home / 'file').exists())

    def test_installer_preserves_custom_configuration(self):
        self.run_script('link_install.zsh')
        config = self.home / 'Projects/Link/slnk.conf'
        config.write_text('ruby|~/ruby|rb\n')
        self.run_script('link_install.zsh')
        self.assertEqual(config.read_text(), 'ruby|~/ruby|rb\n')
        self.assertTrue(config.with_name('slnk.conf.example').is_file())
        self.assertEqual((self.home / 'Link/slnk.zsh').resolve(),
                         self.home / 'Projects/Link/slnk.zsh')

    def test_installer_missing_payload_makes_no_changes(self):
        package = self.root / 'incomplete'
        package.mkdir()
        shutil.copy2(ROOT / 'link_install.zsh', package / 'link_install.zsh')
        result = subprocess.run(['zsh', str(package / 'link_install.zsh')], env=self.env,
                                capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.home / 'Projects').exists())

    def test_link_cleanup_recursive_with_exclusions(self):
        self.dest.mkdir()
        (self.dest / 'nested').mkdir()
        for name in ['stale', 'nested/old']:
            (self.dest / name).symlink_to(self.root / 'missing')
        (self.dest / '.hidden').symlink_to(self.root / 'missing')
        (self.dest / '.git').mkdir()
        (self.dest / '.git/old').symlink_to(self.root / 'missing')
        external = self.root / 'external'
        external.mkdir()
        (external / 'old').symlink_to(self.root / 'missing')
        (self.dest / 'dir-alias').symlink_to(external)
        (self.dest / 'keep-file').write_text('keep')
        original = self.write('current')
        (self.dest / 'valid').symlink_to(original)
        self.run_script('link.zsh', self.source, self.dest)
        self.assertFalse((self.dest / 'stale').is_symlink())
        self.assertFalse((self.dest / 'nested/old').is_symlink())
        self.assertTrue((self.dest / '.hidden').is_symlink())
        self.assertTrue((self.dest / '.git/old').is_symlink())
        self.assertTrue((external / 'old').is_symlink())
        self.assertTrue((self.dest / 'valid').is_symlink())
        self.assertEqual((self.dest / 'keep-file').read_text(), 'keep')

    def test_slnk_cleanup_direct_only(self):
        self.dest.mkdir()
        (self.dest / 'stale').symlink_to(self.root / 'missing')
        (self.dest / '.hidden').symlink_to(self.root / 'missing')
        (self.dest / 'nested').mkdir()
        (self.dest / 'nested/old').symlink_to(self.root / 'missing')
        self.slnk(self.source)
        self.assertFalse((self.dest / 'stale').is_symlink())
        self.assertTrue((self.dest / '.hidden').is_symlink())
        self.assertTrue((self.dest / 'nested/old').is_symlink())

    def test_missing_source_does_not_trigger_cleanup(self):
        self.dest.mkdir()
        stale = self.dest / 'stale'
        stale.symlink_to(self.root / 'missing')
        self.slnk(self.root / 'missing-source', self.source, expected=1)
        self.assertTrue(stale.is_symlink())
        self.run_script('link.zsh', self.root / 'missing-source', self.dest, expected=1)
        self.assertTrue(stale.is_symlink())

    def test_cleanup_failure_returns_error_and_preserves_link(self):
        self.dest.mkdir()
        stale = self.dest / 'stale'
        stale.symlink_to(self.root / 'missing')
        self.fail_command('unlink')
        self.slnk(self.source, expected=1)
        self.assertTrue(stale.is_symlink())
        self.run_script('link.zsh', self.source, self.dest, expected=1)
        self.assertTrue(stale.is_symlink())

    def test_version_options_have_no_side_effects(self):
        for name in ['link.zsh', 'slnk.zsh', 'link_install.zsh']:
            for option in ['-v', '--version']:
                result = self.run_script(name, option)
                self.assertEqual(result.stdout.strip(), f'{name} Version 1.2b')
                self.assertFalse((self.home / 'Projects').exists())

    def test_link_real_file_backup_sequence(self):
        original = self.write('sub/file')
        target = self.dest / 'sub/file'
        target.parent.mkdir(parents=True)
        date = datetime.now().strftime('%Y%m%d')
        for number in range(3):
            if target.is_symlink():
                target.unlink()
            target.write_text(f'original {number}')
            self.run_script('link.zsh', self.source, self.dest)
            suffix = '' if number == 0 else f'.{number}'
            backup = Path(str(target) + '.' + date + suffix)
            self.assertEqual(backup.read_text(), f'original {number}')
            self.assertEqual(target.resolve(), original)

    def test_link_restores_real_file_on_creation_failure(self):
        self.write('file')
        self.dest.mkdir()
        target = self.dest / 'file'
        target.write_text('preserve me')
        self.fail_command('ln')
        self.run_script('link.zsh', self.source, self.dest, expected=1)
        self.assertFalse(target.is_symlink())
        self.assertEqual(target.read_text(), 'preserve me')

    def prepare_dotfile(self):
        dotfiles = self.home / 'Projects/Dotfiles'
        dotfiles.mkdir(parents=True)
        tracked = dotfiles / '.zshrc'
        tracked.write_text('original dotfile')
        tracked.chmod(0o640)
        (self.home / '.zshrc').symlink_to(tracked)
        replacement = self.root / 'new-zshrc'
        replacement.write_text('new dotfile')
        return tracked, replacement

    def test_default_install_does_not_touch_dotfile(self):
        tracked, _ = self.prepare_dotfile()
        self.run_script('link_install.zsh')
        self.assertEqual(tracked.read_text(), 'original dotfile')
        self.assertTrue((self.home / '.zshrc').is_symlink())
        self.assertFalse(list(self.home.glob('.zshrc.????????*')))

    def test_dotfile_update_preserves_symlink_and_numbers_backups(self):
        tracked, replacement = self.prepare_dotfile()
        date = datetime.now().strftime('%Y%m%d')
        for n in range(3):
            replacement.write_text(f'new {n}')
            old = tracked.read_text()
            self.run_script('link_install.zsh', '--update-zshrc', replacement)
            suffix = '' if n == 0 else f'.{n}'
            backup = self.home / ('.zshrc.' + date + suffix)
            self.assertFalse(backup.is_symlink())
            self.assertEqual(backup.read_text(), old)
            self.assertEqual(tracked.read_text(), f'new {n}')
            self.assertEqual(tracked.stat().st_mode & 0o777, 0o640)
            self.assertTrue((self.home / '.zshrc').is_symlink())
            self.assertEqual((self.home / '.zshrc').resolve(), tracked)

    def test_dotfile_update_failure_preserves_original(self):
        tracked, replacement = self.prepare_dotfile()
        self.run_script('link_install.zsh')
        self.run_script('link_install.zsh')  # Create the default comparison file too.
        self.fail_command('mv')
        self.run_script('link_install.zsh', '--update-zshrc', replacement, expected=1)
        self.assertEqual(tracked.read_text(), 'original dotfile')
        self.assertTrue((self.home / '.zshrc').is_symlink())
        self.assertTrue(list(self.home.glob('.zshrc.????????')))

    def test_dotfile_wrong_link_is_rejected_before_install(self):
        tracked, replacement = self.prepare_dotfile()
        home_link = self.home / '.zshrc'
        home_link.unlink()
        home_link.write_text('untracked')
        self.run_script('link_install.zsh', '--update-zshrc', replacement, expected=1)
        self.assertEqual(tracked.read_text(), 'original dotfile')
        self.assertFalse((self.home / 'Projects/Link').exists())

    def test_link_backup_avoids_planned_source_names(self):
        date = datetime.now().strftime('%Y%m%d')
        self.write('file')
        self.write('file.' + date)
        self.dest.mkdir()
        (self.dest / 'file').write_text('original')
        self.run_script('link.zsh', self.source, self.dest)
        self.assertEqual((self.dest / ('file.' + date + '.1')).read_text(), 'original')
        self.assertTrue((self.dest / ('file.' + date)).is_symlink())

    def test_slnk_backup_avoids_planned_source_names(self):
        date = datetime.now().strftime('%Y%m%d')
        self.config.write_text(f'shell|{self.dest}|sh,{date}\n')
        self.write('file.sh')
        self.write('file.sh.' + date)
        self.dest.mkdir()
        (self.dest / 'file.sh').write_text('original')
        self.slnk(self.source)
        self.assertEqual((self.dest / ('file.sh.' + date + '.1')).read_text(), 'original')
        self.assertTrue((self.dest / ('file.sh.' + date)).is_symlink())


if __name__ == '__main__':
    unittest.main()
