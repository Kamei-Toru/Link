# Review — Version 1.3

## Scope and baseline

Reviewed the actual Version 1.2b files under ~/Projects/Link, including all three
zsh scripts and test/test_link_scripts.py. The existing command is slnk.zsh;
no slink.zsh alias or rename was introduced. Changes were prepared separately;
the real project, command links, home configuration, and Git history were not
modified during verification. The scripts now acknowledge ChatGPT assistance.

## Findings and applied corrections

1. Language routing was already configuration-driven. Hardcoding new language
   branches would be unnecessary and risk changing existing behavior. Enabled
   Swift (swift,swiftmodule,swiftinterface), Ruby (rb,rake), and JavaScript (js,mjs,cjs) in slnk.conf and
   added the corresponding help examples. Chosen default destinations are
   ~/Swscripts, ~/Rbscripts, and ~/Jsscripts.
2. Ruby and JavaScript previously appeared only as commented config examples.
   Their entries are now active; Swift is a new active entry. Existing Shell,
   Perl, and Python entries remain unchanged.
3. The installer deliberately preserves existing slnk.conf. Replacing only
   scripts would not activate new languages in existing installations. Kept
   installer behavior unchanged and supplied a separate no-backup placement
   shell that preserves existing language entries and custom destinations while
   appending missing Swift, Ruby, and JavaScript entries.
4. Appending defaults can conflict with extensions already assigned to another
   language. The placement shell validates the merged configuration before
   writing; a conflict aborts without silently reassigning extensions. Existing
   entries for the three language keys remain authoritative.
5. Updated zsh version comments/constants/help to 1.3; updated test metadata and
   expected version output, config metadata, README and this review. Added
   ChatGPT-attribution comments to all zsh scripts and the Python test script.
6. The requested no-backup policy applies to this placement operation. Removing
   runtime backup behavior from link, slnk, or the existing installer would be an
   unspecified behavioral change, so those mechanisms remain unchanged.

## Compatibility and observable effects

- Existing arguments, options, version-output shape, error messages, summary
  formats, link handling, backups, exit statuses, and cleanup logic are retained.
- link.zsh and link_install.zsh differ only in version metadata/help and the
  attribution comment. Slnk's processing logic is unchanged.
- The default config now routes three more languages and creates their three
  destination directories, even with no matching scripts. Existing source/root
  overlap checks and destination cleanup also apply to these destinations.
- Explicit custom configs remain explicit: no implicit language defaults are
  injected by slnk itself. An existing custom language definition is not
  overwritten by the placement shell.
- The standard installer still creates dated backups and preserves slnk.conf.
  The separate placement shell overwrites release files without backups and
  does not invoke the installer or update .zshrc, PATH, or Git state.
- The Python regression script retains unittest's CLI; -v remains verbosity.

## Verification performed

- zsh syntax checks passed for link.zsh, slnk.zsh, link_install.zsh and the
  separate no-backup placement shell.
- All 33 Python unittest cases passed on macOS: all previous 28 cases plus five
  new cases for six-language routing with mixed-case extensions, destination
  creation for empty sources, explicit custom-config isolation, and installer
  preservation of an old config while supplying the expanded example, and exclusion of Swift module directories.
- Confirmed metadata-normalized link/install scripts match the actual baseline;
  Slnk matches after normalizing metadata and its added help examples.
- Separately executed the placement shell twice under an isolated HOME. Verified
  custom Shell/Ruby destinations remain, missing language definitions are added
  only once, command links resolve correctly, and no deployment backups appear.
- A conflicting extension assignment was rejected before installed script or
  configuration contents changed.
- Existing regression coverage includes missing sources, link replacement,
  dated backups, failed-operation recovery, cleanup, unusual filenames, and
  tracked .zshrc updates using a temporary HOME.

## Verification not performed and remaining limits

- GNU/Linux execution, alternate zsh releases, and case-insensitive filesystem
  collision behavior were not tested. The existing GNU mv -T branch is unchanged.
- Swift, Ruby, and JavaScript programs were not executed. Link creation uses
  extensions and does not require these language runtimes.
- No real installation, real .zshrc modification, Git commit, or Git push was
  performed. The user can run the supplied placement shell to apply the release.
- Concurrent changes, hostile directory replacement, process termination, power
  loss and whole-release rollback remain outside the guarantee. Updates are not
  transactional across files. No-backup deployment is intentionally irreversible
  without an external copy or Git history.


## Swift extension update (Version 1.3 retained)

- Added swiftmodule and swiftinterface to Swift configuration and help examples;
  the linking engine and version are unchanged.
- Expanded default-routing regression coverage to include both extensions and
  uppercase forms. Repeated runs still skip the identical links.
- Confirmed .swiftmodule directories remain excluded, preserving direct regular-
  file scanning and avoiding an unintended recursive or package-linking change.
- Corrected placement migration: previously an already-defined Swift entry would
  be retained without the new extensions. The placement shell now appends only
  the missing extensions, retaining custom destinations and existing extensions.
- Verified migration twice under an isolated HOME and rejected conflicting
  ownership of the added extensions before any installed content changed.
- Swift compiler execution, binary-module compatibility, and GNU/Linux execution
  were not tested. These tools only create filesystem links.
