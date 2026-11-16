#!/bin/zsh
# Mirror visible regular files as symbolic links.
emulate -LR zsh
setopt NO_UNSET PIPE_FAIL
unsetopt GLOB_DOTS
usage() {
  cat <<'HELP'
link.zsh - Link visible source files, preserving subdirectory structure.

Usage:
  link.zsh [--] SOURCE DESTINATION
  link.zsh -h | --help

Arguments:
  SOURCE       Existing directory containing original files.
  DESTINATION  Directory for links; created with parents if missing.

Options:
  -h, --help   Display help and exit.
  --           Allow a source path beginning with a dash.

Behavior:
  Preserve relative paths and basenames; use absolute link targets.
  Exclude dotfiles, dot-directories (including .git), and source symlinks.
  Keep links resolving to any regular file inside SOURCE; replace other links.
  Never overwrite non-link entries or follow destination parent symlinks.
  Source and destination must be separate, non-overlapping directory trees.
  After successful linking, remove dangling visible links recursively in DESTINATION.
  Hidden entries and symlinked directory contents are excluded from cleanup.
  Empty directories are not mirrored. Earlier changes are not rolled back.
  Do not modify either tree concurrently while the script runs.

Examples:
  ./link.zsh "$HOME/Projects/Repo" "$HOME/Repo"
  ./link.zsh "./source files" "./links"
  ./link.zsh -- -source -destination

Exit status:
  0  Success, empty source, or help displayed.
  1  Invalid directory, destination conflict, or filesystem failure.
  2  Invalid arguments or unknown option.

Errors are written to standard error.
HELP
}
error() { print -ru2 -- "Error: $1"; }
if (( $# == 1 )) && [[ $1 == -h || $1 == --help || $1 == '—help' ]]; then
  usage; exit 0
fi
if [[ ${1-} == -- ]]; then
  shift
elif [[ ${1-} == -* ]]; then
  error 'Unknown option. Use --help, or -- before dash-prefixed paths.'; exit 2
fi
if (( $# != 2 )) || [[ -z $1 || -z $2 ]]; then
  error 'Expected SOURCE and DESTINATION. Use --help for usage.'; exit 2
fi
if [[ ! -d $1 || ! -r $1 || ! -x $1 ]]; then
  error "Source directory does not exist or is not accessible: $1"; exit 1
fi
source_dir=${1:A}
destination=${2:A}
within() { [[ $2 == / || $1 == "$2" || $1 == "$2/"* ]]; }
if within "$destination" "$source_dir" || within "$source_dir" "$destination"; then
  error 'Source and destination directory trees must not overlap.'; exit 1
fi
if [[ ! -d $2 && ( -e $2 || -L $2 ) ]]; then
  error "Destination is not a directory: $2"; exit 1
fi
# Check traversal access before the glob, which can silently skip unreadable trees.
for directory in "$source_dir" "$source_dir"/**/*(N/); do
  if [[ ! -r $directory || ! -x $directory ]]; then
    error "Source subdirectory is not accessible: $directory"; exit 1
  fi
done
typeset -a files
files=( "$source_dir"/**/*(N.) )
check_parents() {
  local relative=$1 component parent=$destination
  local -a components
  components=( "${(@s:/:)relative}" )
  components[-1]=()
  for component in "${components[@]}"; do
    parent="$parent/$component"
    if [[ -L $parent || ( -e $parent && ! -d $parent ) ]]; then
      error "Destination parent is a symbolic link or is not a directory: $parent"
      return 1
    fi
  done
  return 0
}
for file in "${files[@]}"; do
  relative=${file#"$source_dir/"}
  check_parents "$relative" || exit 1
  target="$destination/$relative"
  if [[ ! -L $target && -e $target ]]; then
    error "Destination entry exists and is not a symbolic link: $target"; exit 1
  fi
done
if ! command mkdir -p -- "$destination"; then
  error "Cannot create destination directory: $destination"; exit 1
fi
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

integer created=0 skipped=0 replaced=0
for file in "${files[@]}"; do
  relative=${file#"$source_dir/"}
  target="$destination/$relative"
  check_parents "$relative" || exit 1
  if ! command mkdir -p -- "${target:h}"; then
    error "Cannot create destination subdirectory: ${target:h}"; exit 1
  fi
  if [[ -L $target ]]; then
    resolved=${target:A}
    if [[ -f $resolved ]] && within "$resolved" "$source_dir"; then
      (( skipped += 1 )); continue
    fi
    if ! replace_link "$file" "$target"; then
      error "Cannot replace symbolic link: $target"; exit 1
    fi
    (( replaced += 1 )); (( created += 1 )); continue
  elif [[ -e $target ]]; then
    error "Destination entry already exists: $target"; exit 1
  fi
  if ! command ln -s -- "$file" "$target"; then
    error "Cannot create symbolic link: $target"; exit 1
  fi
  (( created += 1 ))
done
# Do not follow symlinked directories or include hidden descendants.
integer removed=0 cleanup_failed=0
for directory in "$destination" "$destination"/**/*(N/); do
  if [[ ! -r $directory || ! -x $directory ]]; then
    error "Cannot inspect destination for broken links: $directory"
    exit 1
  fi
done
for candidate in "$destination"/**/*(N@); do
  if [[ -L $candidate && ! -e $candidate ]]; then
    if command unlink -- "$candidate"; then
      print -r -- "Removed broken link: $candidate"
      (( removed += 1 ))
    else
      error "Cannot remove broken link: $candidate"; cleanup_failed=1
    fi
  fi
done
print -r -- "Done: $created link(s) created ($replaced replaced), $skipped skipped, $removed broken link(s) removed."
exit $cleanup_failed
