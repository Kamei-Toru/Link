# Script review — Version 1.2b

## Changes

| Finding in the previous package | Improvement |
| --- | --- |
| Updating a link removed it before creating the replacement | Prepare a temporary link on the same filesystem, then rename it over the existing link; failed preparation or rename preserves the old link |
| A regular file remained displaced after failed link creation | Attempt to restore its backup when the destination is still absent; report the backup path if restoration fails |
| Reinstallation replaced custom configuration | Preserve slnk.conf and install defaults as slnk.conf.example |
| An incomplete installation package could change files before failing | Validate all required payload files and destination entry types before installation |
| Copy failure could occur after moving the installed file aside | Stage the copy first; attempt restoration after a failed final move |
| Empty configuration tokens could be lost during splitting | Validate exact separator count, explicit fields, and empty extension tokens |
| Recursive globbing could silently skip inaccessible source directories | Check source and visible subdirectory access before linking |
| No reusable regression suite was included | Include 28 standard-library tests, including deliberate ln/mv failures |

The original behavior remains: link preserves subdirectory structure and excludes
hidden descendants; slnk scans directly inside multiple source directories and
supports configurable languages, missing-source continuation, link updates, and
dated numbered backups. Real destination directories and special files are never
replaced by slnk.

## Validation

- zsh syntax checks for link.zsh, slnk.zsh, and link_install.zsh.
- 28 regression tests passed on macOS using zsh.
- Existing integration checks for configurable languages, backup numbering,
  missing-source continuation, and isolated installation also passed.
- ZIP integrity and folder layout verified before delivery.

The GNU/Linux atomic replacement branch is implemented using mv -T but was not
executed in this macOS environment. Tests can be rerun on GNU/Linux with Python 3
and zsh. No real user installation files were changed during verification.

## Remaining limits

These tools assume trusted directories with no concurrent modification. They do
not lock directories or defend against adversarial path changes. Atomic rename
protects replacement of an existing link; an entire run is not transactional.
A crash, power loss, or failed restoration can interrupt regular-file backup or
installation. Backups are retained for manual recovery. Temporary staging cleanup
on abrupt process termination is not guaranteed. Slnk uses extensions rather
than parsing shebangs and does not recurse into source subdirectories.


## Broken-link cleanup update

Both tools now remove dangling visible symbolic links after a successful link
phase. Link scans recursively without following directory symlinks; Slnk scans
each configured destination directly, deduplicating shared destination paths.
Earlier errors skip cleanup. Cleanup failure sets exit status 1. Tests verify
scope, hidden-entry exclusion, normal file/link preservation, missing-source
behavior, and injected unlink failure. Regular dated backups are retained.


## Version 1.2b re-review

Reviewed all three zsh scripts after the changes, including failure paths.

| Script | Version 1.2b changes and review |
| --- | --- |
| link.zsh | Adds version flags, dated numbered regular-file backups, restoration on link-creation failure, and avoidance of planned link names when choosing backup paths |
| slnk.zsh | Adds version flags and reserves planned destination names before selecting backups; existing language routing, cleanup and failure behavior retained |
| link_install.zsh | Renames the installer, adds version flags, installs itself in the repository, preserves configuration, and supports an explicit tracked-dotfile update without replacing the home symlink |

Both version options return before configuration, installation, linking or
cleanup. The dotfile option is opt-in: default installation leaves .zshrc alone.
Tests use isolated HOME directories; the actual user's .zshrc was not modified.
The dotfile backup is a verified regular copy under HOME, not a moved home link.
Its date/suffix selection handles existing files and dangling symbolic links.
A staged rename retains the old tracked file on simulated mv failure.

The 28-test suite and syntax checks passed on macOS. GNU/Linux behavior remains
unexecuted here. Concurrency, abrupt termination and non-transactional multi-file
updates remain the limitations described above.
