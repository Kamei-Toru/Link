# Link and Slnk — Version 1.3

Created with assistance from ChatGPT. All three zsh scripts report Version 1.3.
The command name is `slnk.zsh`, not `slink.zsh`.

## Requirements

zsh 5.x on macOS or GNU/Linux, with standard mkdir, ln, mv, mktemp, rm,
rmdir, unlink, and date utilities. Installation also uses cp, cmp, cat, and
chmod. Python 3 is required only for the tests and the supplied no-backup
placement shell. Swift, Ruby, and JavaScript runtimes are not required to create
links: classification uses filename extensions without executing source files.

## Files

- `link.zsh`: recursively mirror visible regular files as links.
- `slnk.zsh`: link visible scripts directly inside multiple source directories.
- `link_install.zsh`: existing installer, including its optional dotfile update.
- `slnk.conf`: language, destination, and extension definitions.
- `test/test_link_scripts.py`: regression tests.
- `REVIEW.md`: changes, compatibility review, and verification limits.

## Version and help

Each zsh script supports `-v`, `--version`, `-h`, and `--help`.
Version output retains the format `SCRIPT_NAME Version 1.3`.
The Python test script retains unittest's CLI; `-v` means verbose tests there.

```zsh
./link.zsh --version
./slnk.zsh -v
zsh ./link_install.zsh --help
```

## Link usage

```zsh
link.zsh [--] SOURCE DESTINATION
```

SOURCE must be an accessible existing directory. DESTINATION is created with
parents if missing. Source and destination trees must not overlap. Visible
regular files are scanned recursively, preserving relative paths and basenames.
Dotfiles, hidden directories, source symlinks, and empty directories are excluded.
Destination parent symlinks are rejected.

Existing links resolving to any regular file inside SOURCE are skipped, even
if they point to another source file. Other links are atomically replaced using
a staged link. Existing regular files are moved to NAME.yyyymmdd, then
NAME.yyyymmdd.1, .2, etc., inside the corresponding destination subdirectory.
Existing backup paths and planned link names are avoided. Directories and
special files are preserved and reported as errors. Failed link creation after
a backup attempts to restore the original file when the destination is absent.

After successful linking, dangling visible links are removed recursively from
DESTINATION, including stale unrelated links. Hidden entries are excluded and
symlinked directory contents are not traversed. An earlier error skips cleanup.

```zsh
~/Link/link.zsh "$HOME/Projects/Repo" "$HOME/Repo"
```

## Slnk usage

```zsh
slnk.zsh [-c CONFIG] [--] SOURCE [SOURCE ...]
```

`--config` aliases `-c`. Options precede source arguments; use `--` before a
source path beginning with a dash. The default config is slnk.conf beside the
resolved script, including when invoked through ~/Link/slnk.zsh.

Only visible regular files directly inside each SOURCE are scanned. Hidden
entries, source symlinks, subdirectories, and unrecognized extensions are
excluded. Source files do not need executable permission. Extensions are
case-insensitive. Missing or inaccessible sources report English errors and
processing continues; any error makes the final status 1.

```zsh
~/Link/slnk.zsh ~/project-a/scripts ~/project-b/scripts
~/Link/slnk.zsh -c ./custom.conf ./scripts
```

### Configuration and additional languages

Format: `LANGUAGE|DESTINATION|COMMA-SEPARATED EXTENSIONS`.

| Language | Default destination | Extensions |
| --- | --- | --- |
| Shell | ~/Shscripts | sh,zsh,bash,ksh,csh,tcsh,fish |
| Perl | ~/Plscripts | pl,pm |
| Python | ~/Pyscripts | py,pyw |
| Swift | ~/Swscripts | swift,swiftmodule,swiftinterface |
| Ruby | ~/Rbscripts | rb,rake |
| JavaScript | ~/Jsscripts | js,mjs,cjs |

Version 1.3 enables the last three entries in the supplied configuration.
No hardcoded language routing was added. Additional languages remain configurable.
An explicitly supplied custom config does not implicitly gain the new entries.

Each language key and each extension must be unique. Extensions are ASCII
letters or digits, without dots. Paths must be absolute or start with ~/.
Spaces are supported without quotes. Values are plain data, never evaluated as
shell code; variable substitution and shell quoting are not expanded. Blank
lines, full-line # comments, and CRLF files are accepted. Inline comments are
not supported. Missing, unreadable, empty, or malformed configs exit with status
2 before destination creation.

All configured destinations are created, even for an empty valid source.
Consequently, the new default config also creates Swscripts, Rbscripts, and
Jsscripts. Existing overlap checks also apply to these destinations.

Links retain basenames and use absolute targets. Links resolving to the same
source file are skipped; different or broken links are atomically replaced.
Regular files receive dated numbered backups before linking; failed creation
attempts restoration. Directories and special files are preserved with errors.
Conflicting source names keep the first source and report an error for the later
source. Repeated source paths are ignored. Source/destination overlap terminates
the run before destination creation.

After an error-free link phase, dangling visible links directly inside every
configured destination are removed, including unrelated stale links. Cleanup
is not recursive, excludes hidden entries, and is skipped after earlier errors.
New destinations participate in the same existing cleanup policy.

## Existing installer

```zsh
zsh ./link_install.zsh
```

Installs scripts and README in ~/Projects/Link and creates command links for
link.zsh and slnk.zsh in ~/Link. Existing slnk.conf is preserved; packaged
defaults are written as slnk.conf.example. Therefore, merely running the
installer does not enable new languages in an existing config. Merge the three
new entries manually, or use the supplied no-backup placement shell.

The installer's existing dated backup behavior is unchanged. The placement
shell is separate: it replaces release files without backups, preserves custom
config entries, and appends only missing language entries. It aborts before
writing if a new entry conflicts with an existing extension assignment.
Neither method commits or pushes Git changes or changes PATH.

### Optional tracked .zshrc update

```zsh
zsh ./link_install.zsh --update-zshrc /absolute/path/to/new-zshrc
```

Default installation leaves .zshrc untouched. The optional update requires
~/.zshrc to resolve exactly to the real ~/Projects/Dotfiles/.zshrc. Original
contents are copied to a verified regular backup ~/.zshrc.yyyymmdd[.N]. The
tracked file is updated with its mode preserved; the home symlink remains.
Identical content is skipped. This existing runtime backup behavior is unchanged.
The no-backup placement shell does not invoke this option or modify .zshrc.

## Exit statuses and output

Both linking tools retain statuses: 0 success/help/version, 1 directory,
conflict or filesystem error, and 2 invalid arguments/configuration. The installer
retains 0 success/help/version, 1 filesystem error, and 2 invalid arguments.

English errors are written to standard error. Existing summary formats remain:

```text
Done: C link(s) created (R replaced), S skipped, B file(s) backed up, D broken link(s) removed.
Done: C link(s) created (U updated), S skipped, B file(s) backed up, D broken link(s) removed.
```

The first line is link; the second is slnk. Created includes replacements.
Backup and removal messages retain their existing formats.

## Tests and limits

```sh
python3 -m unittest discover -s test -v
```

33 tests pass on macOS, including the previous 28 cases and five new cases for
six-language routing, empty-source destination creation, explicit custom config
behavior, and the installer preserving an old config while supplying new defaults, and continued exclusion of .swiftmodule directories.

Use trusted directories without concurrent modification. There is no directory
locking or whole-run transaction. Earlier operations are not rolled back after
later errors. Atomic replacement stages beside the destination; macOS uses
mv -h and GNU/Linux uses mv -T. Abrupt termination can interrupt backup or
installation and leave staging files. Linux execution and real Swift/Ruby/JS
program execution were not tested; creating links does not run those programs.


### Swift module and interface files

Version remains 1.3. Swift also includes regular files ending in .swiftmodule
and .swiftinterface, case-insensitively. The existing direct-file scan is
unchanged: a directory named Package.swiftmodule is not linked or traversed.
The supplied placement shell adds these two extensions to an existing Swift
entry while preserving its destination and other extensions. Repeated placement
does not duplicate entries. Conflicting extension ownership aborts before writes.
The standard installer still preserves slnk.conf; merge the extensions manually
or use the supplied placement shell.
