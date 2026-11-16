# Link and Slnk

Create symbolic links to visible regular files while preserving source subdirectory
structure. Dotfiles and dot-directories, including `.git`, are excluded at every depth.

## Requirements

zsh 5.x on macOS or GNU/Linux, with standard `mkdir`, `ln`, `mv`, `mktemp`,
`rm`, `rmdir`, and `date`. Installation additionally uses `cp`, `cmp`, and `chmod`.
Atomic link updates use BSD `mv -h` on macOS and GNU `mv -T` on Linux.

## Usage

```zsh
chmod +x Link/link.zsh
./Link/link.zsh "$HOME/Projects/Repo" "$HOME/Repo"
./Link/link.zsh -h
./Link/link.zsh --help
```

```text
link.zsh [--] SOURCE DESTINATION
```

| Argument | Purpose | If missing |
| --- | --- | --- |
| SOURCE (first) | Original files | English error on standard error; exit 1 |
| DESTINATION (second) | Directory receiving links | Create it, including parent directories |

The source is validated before creating the destination. An empty source succeeds
and creates the destination if needed. Quote paths containing spaces. Use `--`
before a source path beginning with a dash. The typographic `—help` is also accepted.

## File mapping

| Source | Destination |
| --- | --- |
| `SOURCE/a/README.md` | `DESTINATION/a/README.md` |
| `SOURCE/b/README.md` | `DESTINATION/b/README.md` |
| `SOURCE/.env` | Excluded |
| `SOURCE/a/.git/HEAD` | Excluded |

Links retain their original basenames and use absolute targets. Parent directories
are created as needed. Empty directories, source symlinks, symlinked directories,
and special files are not mirrored. An explicitly supplied source root may itself
have a dot-prefixed name; hidden descendants remain excluded.

## Existing entries

| Destination entry | Action |
| --- | --- |
| No entry | Create a link |
| Link resolving to any regular file inside SOURCE | Skip, even if it points to another source file |
| Link resolving outside SOURCE | Replace |
| Broken link or link resolving to a directory | Replace |
| Non-link file, directory, or other entry | Error; preserve the entry |

Containment uses resolved absolute paths and directory boundaries. Relative links
are resolved relative to their containing directory. Source and destination trees
must not overlap. Existing parent directories below DESTINATION must not be
symlinks; explicitly supplied roots may resolve through symlinks. Known conflicts
are checked before destination changes. Hidden entries, real files, directories, and valid links remain untouched.
After successful linking, dangling visible links are removed recursively from
DESTINATION, including stale links with no corresponding source file. Cleanup
does not traverse symlinked directories. An earlier error skips cleanup; a cleanup
error returns status 1 and earlier successful deletions are not rolled back.

## Exit status

| Status | Meaning |
| --- | --- |
| 0 | Success, empty source, or help displayed |
| 1 | Invalid directory, destination conflict, or filesystem failure |
| 2 | Invalid arguments or unknown option |

Success prints created, replaced, and skipped counts. Created includes replacements.
Errors are written to standard error.

## Operational notes

Use trusted directories and do not modify either tree concurrently. Changes are
not transactional and earlier successful operations are not rolled back. Existing
links are replaced by staging a new link beside the destination and renaming it
over the old link. Preparation or rename failure leaves the old link intact.
Source file contents are never modified.

# Slnk — script links by language

`slnk.zsh` belongs to this same repository and is separate from `link.zsh`.
It scans visible regular files directly inside one or more source directories;
subdirectories, dotfiles, source symlinks, and unrecognized extensions are excluded.
Executable permission is not required. Extensions are matched case-insensitively.

## Installation for both tools

From the extracted package's parent directory, run:

```zsh
zsh ./Link/install.zsh
```

This installs `link.zsh`, `slnk.zsh`, `slnk.conf`, and this merged `README.md` in
`~/Projects/Link/`. It creates `~/Link/link.zsh` and `~/Link/slnk.zsh` as symbolic
links to those scripts. Changed installed files are backed up with `.yyyymmdd`, then `.yyyymmdd.1`,
`.2`, etc. An existing `slnk.conf` is preserved; packaged defaults are written
to `slnk.conf.example` for comparison. Identical files and correct command links
are preserved. Other command entries are backed up. Real directories are never
replaced. The installer does not edit PATH or push anything to GitHub.

## Slnk usage

```zsh
~/Link/slnk.zsh ~/project-a/scripts ~/project-b/scripts
~/Link/slnk.zsh -c ./custom.conf ./scripts
~/Link/slnk.zsh -h
~/Link/slnk.zsh --help
```

Options must precede source arguments. `--config` aliases `-c`; use `--` before
a source path beginning with a dash. Missing or inaccessible source directories
produce English errors on standard error and processing continues with subsequent
arguments. The final exit status is 1 if any such error occurred.

## Extensible configuration

The default configuration is `slnk.conf` beside the resolved script, so invoking
`~/Link/slnk.zsh` reads `~/Projects/Link/slnk.conf`. A missing configuration is an
error. The format has changed from the initial Slnk version:

```text
LANGUAGE|DESTINATION|COMMA-SEPARATED EXTENSIONS
```

Default entries:

```text
shell|~/Shscripts|sh,zsh,bash,ksh,csh,tcsh,fish
perl|~/Plscripts|pl,pm
python|~/Pyscripts|py,pyw
```

Add other languages without modifying the script, for example:

```text
ruby|~/Rbscripts|rb,rake
javascript|~/Jsscripts|js,mjs,cjs
```

All configured destination directories are created at startup, even if no files
match. Each language must appear once; each extension must belong to only one
language. Extensions contain ASCII letters or digits, without leading dots.
Paths must be absolute or start with `~/`; spaces are supported without quoting.
Values are plain data and are never sourced or evaluated. Shell substitutions,
variables, and quotes are not expanded. `|` is reserved as the field separator.
Blank lines and full-line `#` comments are accepted, including CRLF files.
Configuration errors terminate with status 2 before creating destinations.

## Slnk replacement and backups

| Existing destination entry | Action |
| --- | --- |
| No entry | Create an absolute link retaining the source basename |
| Link resolving to the same source file | Skip |
| Link to another file, or a broken link | Remove the old link and create the requested link |
| Regular file | Move to a dated backup, then create the link |
| Directory or special file | Report an error; preserve it and continue |

For example, `job.py` is backed up as `job.py.20261116`. If that path already
exists, use `job.py.20261116.1`, then `.2`, and so on. Existing backup paths are never overwritten when choosing the next backup
name. The subsequent cleanup also applies to dangling visible links at backup
paths; regular backup files remain untouched. Dates use the machine's
local date at the start of the run. Backups are moved files, not extra copies.

Two distinct source files mapping to the same destination name are a conflict:
the first source encountered wins, the later one reports an error, and unrelated
files continue. Repeated source paths are ignored. Source and configured
destination directory trees must not overlap; overlap terminates with status 1
before creating directories. Explicit roots may resolve through symbolic links.

| Slnk exit status | Meaning |
| --- | --- |
| 0 | Success, no matching files, or help displayed |
| 1 | One or more source, conflict, or filesystem errors |
| 2 | Invalid arguments or configuration |

The created count includes updated links and links replacing backed-up files.
Slnk removes dangling visible links directly inside each configured destination
after a fully successful link phase. It does not recurse or remove hidden links,
valid links, directories, or regular files. Cleanup includes stale links unrelated
to current source names and also runs for an empty valid source. Any earlier error
(including a missing source) skips the entire Slnk cleanup phase. Cleanup errors
return status 1; earlier successful deletions remain. Slnk does not modify source
files or permissions. Use
trusted directories and do not modify them concurrently. Existing links are
updated using a staged link and an atomic rename, including links to directories.
If link creation after a regular-file backup fails, Slnk attempts to restore the
original file when the destination remains absent. If restoration also fails, an
error names the retained backup. Earlier successful operations are not rolled
back. Abrupt termination or power loss can still interrupt a multi-step backup.
Temporary link staging paths are cleaned up when the replacement function exits.


## Verification

The combined packages include Python standard-library regression tests. From the extracted
`Link` directory, run:

```sh
python3 -m unittest discover -s tests -v
```

The tests use temporary directories and an isolated HOME. They cover file/link
preservation when link creation or rename is deliberately failed, backup recovery,
numbered backups, configuration validation, missing sources, parent symlinks,
unusual filenames, and preserving custom settings on reinstall. See `REVIEW.md`
for the review findings and validation limits. The installer installs the runtime
files and README; tests and review notes remain in the downloaded package.


## Download and update

Extract `Link.zip` and run:

```zsh
zsh ./Link/install.zsh
```

The complete package contains both scripts, configuration, shared README,
installer, review notes, and regression tests under a single `Link/` folder.
Existing custom configuration is preserved during installation.
Broken-link cleanup is automatic after a successful run: link.zsh scans visible
entries recursively, and slnk.zsh scans visible entries directly inside each
configured destination. Earlier errors skip cleanup. Each deletion is logged.
