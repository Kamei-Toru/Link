#!/bin/zsh
# Version: 1.3
# Created with assistance from ChatGPT.
# Link scripts by configured extensions; never evaluate configuration as code.
emulate -LR zsh
setopt NO_UNSET EXTENDED_GLOB
unsetopt GLOB_DOTS
readonly SCRIPT_VERSION='1.3'
error() { print -ru2 -- "Error: $1"; }
usage() {
cat <<'HELP'
slnk.zsh - Link scripts from multiple source directories by language.

Usage: slnk.zsh [-c CONFIG] [--] SOURCE [SOURCE ...]
Options:
  -c, --config FILE  Use FILE instead of slnk.conf beside the resolved script.
  -h, --help         Display this help.
  -v, --version      Display Version 1.3 and exit.
  --                End option parsing.
Arguments:
  SOURCE            Directory to scan; multiple sources are supported.
                    Missing or inaccessible sources report an error and are skipped.
Configuration: LANGUAGE|DESTINATION|COMMA-SEPARATED EXTENSIONS
  shell|~/Shscripts|sh,zsh,bash,ksh,csh,tcsh,fish
  perl|~/Plscripts|pl,pm
  python|~/Pyscripts|py,pyw
  swift|~/Swscripts|swift,swiftmodule,swiftinterface
  ruby|~/Rbscripts|rb,rake
  javascript|~/Jsscripts|js,mjs,cjs
Paths must be absolute or start with ~/. Configuration is data, not shell code.
All configured destination directories are created, even with no matching files.
Visible regular files directly inside sources are matched by extension, ignoring
case. Hidden entries, subdirectories, and source symlinks are excluded.
Links retain basenames and use absolute targets. Identical links are skipped;
different or broken links are replaced. Existing regular files are moved to
NAME.yyyymmdd, then NAME.yyyymmdd.1, .2, etc., before linking. Dates use local time.
After successful linking, remove dangling visible links directly inside all
configured destinations, including links unrelated to current source names.
Cleanup is skipped if any earlier operation failed. Hidden entries are excluded.
Directories and special files are preserved and reported as errors. Conflicting
source names are errors; the first source wins. Repeated source paths are ignored.
Examples:
  slnk.zsh "$HOME/project-a/scripts" "$HOME/project-b/scripts"
  slnk.zsh -c ./custom.conf ./scripts
Exit status:
  0  All operations successful, no matching scripts, or help displayed.
  1  One or more source/filesystem/conflict errors (other work continues).
  2  Invalid arguments or configuration (no links created).
Errors go to standard error. Failed link creation attempts to restore a backed-up regular file. Do not
modify either tree concurrently. Source files and permissions are not changed.
HELP
}
config="${0:A:h}/slnk.conf"
while (( $# )); do
  case $1 in
    -h|--help) usage; exit 0 ;;
    -v|--version) print -r -- "slnk.zsh Version $SCRIPT_VERSION"; exit 0 ;;
    -c|--config)
      if (( $# < 2 )) || [[ -z $2 ]]; then error 'Config option requires a file path.'; exit 2; fi
      config=$2; shift 2 ;;
    --) shift; break ;;
    -*) error "Unknown option: $1"; exit 2 ;;
    *) break ;;
  esac
done
if (( $# == 0 )); then error 'Specify at least one source directory. Use --help.'; exit 2; fi
if [[ ! -f $config || ! -r $config ]]; then error "Cannot read configuration file: $config"; exit 2; fi
trim() { REPLY=${1##[[:space:]]#}; REPLY=${REPLY%%[[:space:]]#}; }
typeset -A destinations extension_type
integer line_number=0
while IFS= read -r line || [[ -n $line ]]; do
  (( line_number += 1 ))
  line=${line%$'\r'}; trim "$line"; line=$REPLY
  [[ -z $line || $line == \#* ]] && continue
  separators=${line//[^|]/}
  if [[ $separators != '||' ]]; then error "Expected LANGUAGE|DESTINATION|EXTENSIONS at line $line_number."; exit 2; fi
  trim "${line%%|*}"; language=$REPLY
  rest=${line#*|}
  trim "${rest%%|*}"; dest=$REPLY
  trim "${rest#*|}"; extensions=$REPLY
  if [[ $extensions == ,* || $extensions == *, || $extensions == *,,* ]]; then
    error "Empty extension at configuration line $line_number."; exit 2
  fi
  if [[ -z $language || -z $dest || -z $extensions ]] || (( ${+destinations[$language]} )); then
    error "Empty field or duplicate language at line $line_number."; exit 2
  fi
  if [[ $dest == '~/'* ]]; then dest="$HOME/${dest#\~/}";
  elif [[ $dest != /* ]]; then error "Destination must be absolute or start with ~/: $dest"; exit 2; fi
  destinations[$language]=${dest:A}
  for extension in "${(@s:,:)extensions}"; do
    trim "$extension"; extension=${REPLY:l}
    if [[ $extension != [a-z0-9]## ]] || (( ${+extension_type[$extension]} )); then
      error "Invalid or repeated extension at line $line_number: $extension"; exit 2
    fi
    extension_type[$extension]=$language
  done
done < "$config"
if (( ${#destinations} == 0 )); then error 'Configuration defines no languages.'; exit 2; fi
# Stage beside the destination so replacing a link is a single rename.
# -h (BSD/macOS) / -T (GNU/Linux) prevents following directory symlinks.
replace_link() {
  local original=$1 target=$2 stage
  local -a move_options
  case $OSTYPE in
    darwin*) move_options=(-f -h) ;;
    linux*) move_options=(-f -T) ;;
    *) error "Unsupported platform for atomic link replacement: $OSTYPE"; return 1 ;;
  esac
  stage=$(command mktemp -d "${target:h}/.link-stage.XXXXXXXX") || return 1
  {
    command ln -s -- "$original" "$stage/link" || return 1
    command mv "${move_options[@]}" -- "$stage/link" "$target"
  } always {
    command rm -f -- "$stage/link"
    command rmdir -- "$stage"
  }
}

integer failed=0 created=0 updated=0 skipped=0 backed_up=0
within() { [[ $2 == / || $1 == "$2" || $1 == "$2/"* ]]; }
typeset -a sources
typeset -A seen_sources unavailable claimed
for arg in "$@"; do
  if [[ ! -d $arg || ! -r $arg || ! -x $arg ]]; then
    error "Source directory does not exist or is not accessible: $arg"; failed=1; continue
  fi
  source_dir=${arg:A}
  (( ${+seen_sources[$source_dir]} )) && continue
  seen_sources[$source_dir]=1
  sources+=( "$source_dir" )
done
# Reject overlapping roots before creating any destination directories.
for source_dir in "${sources[@]}"; do
  for dest in "${(@v)destinations}"; do
    if within "$source_dir" "$dest" || within "$dest" "$source_dir"; then
      error "Source and destination trees overlap: $source_dir and $dest"; exit 1
    fi
  done
done
for language in "${(@k)destinations}"; do
  dest=${destinations[$language]}
  if [[ ( -e $dest || -L $dest ) && ! -d $dest ]] || ! command mkdir -p -- "$dest"; then
    error "Cannot create destination directory: $dest"; unavailable[$language]=1; failed=1
  fi
done
# Reserve source-derived names so a backup never becomes a later link target.
typeset -A planned_targets
for source_dir in "${sources[@]}"; do
  for file in "$source_dir"/*(N.); do
    extension=${file:e}; extension=${extension:l}
    (( ${+extension_type[$extension]} )) || continue
    language=${extension_type[$extension]}
    planned_target="${destinations[$language]}/${file:t}"
    planned_targets[$planned_target]=1
  done
done
date_stamp=$(command date +%Y%m%d) || { error 'Cannot determine backup date.'; exit 1; }
for source_dir in "${sources[@]}"; do
  for file in "$source_dir"/*(N.); do
    extension=${file:e}; extension=${extension:l}
    (( ${+extension_type[$extension]} )) || continue
    language=${extension_type[$extension]}
    (( ${+unavailable[$language]} )) && continue
    target="${destinations[$language]}/${file:t}"
    if (( ${+claimed[$target]} )); then
      if [[ ${claimed[$target]} != "$file" ]]; then
        error "Conflicting source name; keeping first source for: $target"; failed=1
      fi
      continue
    fi
    claimed[$target]=$file
    backup=
    if [[ -L $target ]]; then
      if [[ ${target:A} == "$file" && -f $target ]]; then (( skipped += 1 )); continue; fi
      if ! replace_link "$file" "$target"; then
        error "Cannot replace link: $target"; failed=1; continue
      fi
      (( created += 1 )); (( updated += 1 )); continue
    elif [[ -f $target ]]; then
      backup="$target.$date_stamp"; integer suffix=0
      while [[ -e $backup || -L $backup ]] || (( ${+planned_targets[$backup]} )); do
        (( suffix += 1 )); backup="$target.$date_stamp.$suffix"
      done
      if ! command mv -n -- "$target" "$backup" || [[ -e $target || -L $target ]]; then
        error "Cannot back up file: $target"; failed=1; continue
      fi
      (( backed_up += 1 ))
      print -r -- "Backup: $backup"
    elif [[ -e $target ]]; then
      error "Destination is a directory or special file: $target"; failed=1; continue
    fi
    if ! command ln -s -- "$file" "$target"; then
      error "Cannot create link: $target"; failed=1
      if [[ -n $backup && ! -e $target && ! -L $target ]]; then
        if command mv -n -- "$backup" "$target" && [[ ! -e $backup && ! -L $backup ]]; then
          (( backed_up -= 1 ))
          print -ru2 -- "Restored original file: $target"
        else
          error "Cannot restore original file; backup retained at: $backup"
        fi
      fi
      continue
    fi
    (( created += 1 ))
  done
done
# Only clean after a fully successful link phase; do not recurse or inspect dotfiles.
integer removed=0
typeset -A cleaned_destinations
if (( failed == 0 )); then
  for dest in "${(@v)destinations}"; do
    (( ${+cleaned_destinations[$dest]} )) && continue
    cleaned_destinations[$dest]=1
    if [[ ! -r $dest || ! -x $dest ]]; then
      error "Cannot inspect destination for broken links: $dest"; failed=1; continue
    fi
    for candidate in "$dest"/*(N@); do
      if [[ -L $candidate && ! -e $candidate ]]; then
        if command unlink -- "$candidate"; then
          print -r -- "Removed broken link: $candidate"
          (( removed += 1 ))
        else
          error "Cannot remove broken link: $candidate"; failed=1
        fi
      fi
    done
  done
else
  print -ru2 -- 'Broken-link cleanup skipped because earlier errors occurred.'
fi
print -r -- "Done: $created link(s) created ($updated updated), $skipped skipped, $backed_up file(s) backed up, $removed broken link(s) removed."
exit $failed
