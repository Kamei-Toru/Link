#!/bin/zsh
# Install the package; preserve user configuration and back up changed files.
# Version: 1.1
# This script was generated using GitHub.
emulate -LR zsh
setopt NO_UNSET
error() { print -ru2 -- "Error: $1"; }
if (( $# )); then
  if (( $# == 1 )) && [[ $1 == -h || $1 == --help ]]; then
    print -r -- 'Usage: zsh install.zsh
Install scripts in ~/Projects/Link and command links in ~/Link.
Existing slnk.conf is preserved; packaged defaults go to slnk.conf.example.
Changed files are backed up as NAME.yyyymmdd[.N].
Exit status: 0 success/help; 1 filesystem error; 2 invalid arguments.
Do not modify installation directories concurrently.'
    exit 0
  fi
  error 'Unexpected arguments. Use --help.'; exit 2
fi
root=${0:A:h}
repo="$HOME/Projects/Link"
links="$HOME/Link"
stamp=$(command date +%Y%m%d) || exit 1
# Check all package files and destination types before making changes.
for name in link.zsh slnk.zsh slnk.conf README.md; do
  if [[ ! -f "$root/$name" || ! -r "$root/$name" ]]; then
    error "Missing or unreadable package file: $root/$name"; exit 1
  fi
done
for target in "$repo" "$links"; do
  if [[ ( -e $target || -L $target ) && ! -d $target ]]; then
    error "Installation root is not a directory: $target"; exit 1
  fi
done
for name in link.zsh slnk.zsh slnk.conf slnk.conf.example README.md; do
  if [[ -e "$repo/$name" && ! -f "$repo/$name" ]]; then
    error "Installation entry is not a regular file: $repo/$name"; exit 1
  fi
done
for name in link.zsh slnk.zsh; do
  if [[ -e "$links/$name" && ! -f "$links/$name" && ! -L "$links/$name" ]]; then
    error "Command entry is a directory or special file: $links/$name"; exit 1
  fi
done
backup_entry() {
  local entry=$1
  REPLY="$entry.$stamp"
  integer n=0
  while [[ -e $REPLY || -L $REPLY ]]; do
    (( n += 1 )); REPLY="$entry.$stamp.$n"
  done
  command mv -n -- "$entry" "$REPLY" || return 1
  [[ ! -e $entry && ! -L $entry ]] || return 1
  print -r -- "Backup: $REPLY"
}
command mkdir -p -- "$repo" "$links" || exit 1
# Copy to a staging file before backing up the installed version.
install_file() {
  local source_file=$1 target=$2 stage backup=
  [[ ${source_file:A} == ${target:A} ]] && return 0
  if [[ -f $target && ! -L $target ]] && command cmp -s -- "$source_file" "$target"; then return 0; fi
  stage=$(command mktemp "$repo/.install-stage.XXXXXXXX") || return 1
  {
    command cp -p -- "$source_file" "$stage" || return 1
    if [[ -e $target || -L $target ]]; then
      backup_entry "$target" || return 1
      backup=$REPLY
    fi
    if ! command mv -n -- "$stage" "$target" || [[ -e $stage ]]; then
      error "Cannot install: $target"
      if [[ -n $backup && ! -e $target && ! -L $target ]]; then
        command mv -n -- "$backup" "$target" || error "Restore failed; original retained at: $backup"
      fi
      return 1
    fi
  } always {
    command rm -f -- "$stage"
  }
}
for name in link.zsh slnk.zsh README.md; do
  install_file "$root/$name" "$repo/$name" || exit 1
done
if [[ -e "$repo/slnk.conf" || -L "$repo/slnk.conf" ]]; then
  if [[ ! -f "$repo/slnk.conf" ]]; then error 'Existing slnk.conf is not a readable regular file.'; exit 1; fi
  print -r -- "Preserved configuration: $repo/slnk.conf"
  install_file "$root/slnk.conf" "$repo/slnk.conf.example" || exit 1
else
  install_file "$root/slnk.conf" "$repo/slnk.conf" || exit 1
fi
command chmod +x "$repo/link.zsh" "$repo/slnk.zsh" || exit 1
for name in link.zsh slnk.zsh; do
  target="$links/$name"; source_file="$repo/$name"
  [[ -L $target && ${target:A} == ${source_file:A} ]] && continue
  backup=
  # Prepare the new link before moving any existing entry.
  stage=$(command mktemp -d "$links/.install-stage.XXXXXXXX") || exit 1
  {
    command ln -s -- "$source_file" "$stage/link" || exit 1
    if [[ -e $target || -L $target ]]; then backup_entry "$target" || exit 1; backup=$REPLY; fi
    if ! command mv -n -- "$stage/link" "$target" || [[ -L "$stage/link" ]]; then
      error "Cannot install command link: $target"
      if [[ -n $backup && ! -e $target && ! -L $target ]]; then
        command mv -n -- "$backup" "$target" || error "Restore failed; original retained at: $backup"
      fi
      exit 1
    fi
  } always {
    command rm -f -- "$stage/link"
    command rmdir -- "$stage"
  }
done
print -r -- "Installed scripts in $repo and links in $links."
