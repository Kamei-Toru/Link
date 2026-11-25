#!/bin/zsh
# Version: 1.3
# Created with assistance from ChatGPT.
# Install the package; preserve user configuration and back up changed files.
emulate -LR zsh
setopt NO_UNSET
readonly SCRIPT_VERSION='1.3'
error() { print -ru2 -- "Error: $1"; }
zshrc_input=
while (( $# )); do
  case $1 in
    -v|--version) print -r -- "link_install.zsh Version $SCRIPT_VERSION"; exit 0 ;;
    -h|--help)
      print -r -- 'link_install.zsh — Version 1.3
Usage: zsh link_install.zsh [--update-zshrc FILE]
  -h, --help             Display help.
  -v, --version          Display the script version.
  --update-zshrc FILE    Explicitly replace the tracked .zshrc with FILE contents.
Install scripts in ~/Projects/Link and command links in ~/Link.
Existing slnk.conf is preserved; defaults go to slnk.conf.example.
Changed files are backed up as NAME.yyyymmdd[.N].
By default .zshrc is untouched. The optional update requires ~/.zshrc to resolve
exactly to ~/Projects/Dotfiles/.zshrc. Its real contents are copied to a regular
backup ~/.zshrc.yyyymmdd[.N]; the tracked file is updated and the link is kept.
Exit status: 0 success/help/version; 1 filesystem error; 2 invalid arguments.
Do not modify installation directories concurrently.'
      exit 0 ;;
    --update-zshrc)
      if (( $# < 2 )) || [[ -z $2 || -n $zshrc_input ]]; then
        error 'Specify --update-zshrc FILE at most once.'; exit 2
      fi
      zshrc_input=${2:A}; shift 2 ;;
    *) error "Unexpected argument: $1. Use --help."; exit 2 ;;
  esac
done
root=${0:A:h}
repo="$HOME/Projects/Link"
links="$HOME/Link"
stamp=$(command date +%Y%m%d) || exit 1
# Validate an explicitly requested dotfile update before installation changes.
zshrc="$HOME/Projects/Dotfiles/.zshrc"
home_zshrc="$HOME/.zshrc"
if [[ -n $zshrc_input ]]; then
  if [[ ! -f $zshrc_input || ! -r $zshrc_input || ! -f $zshrc || ! -r $zshrc || -L $zshrc ||
        ! -L "$HOME/.zshrc" || ${home_zshrc:A} != ${zshrc:A} ]]; then
    error 'The .zshrc update requires readable input, a real ~/Projects/Dotfiles/.zshrc, and ~/.zshrc linked to it.'
    exit 1
  fi
fi
# Check all package files and destination types before making changes.
for name in link.zsh slnk.zsh link_install.zsh slnk.conf README.md; do
  if [[ ! -f "$root/$name" || ! -r "$root/$name" ]]; then
    error "Missing or unreadable package file: $root/$name"; exit 1
  fi
done
for target in "$repo" "$links"; do
  if [[ ( -e $target || -L $target ) && ! -d $target ]]; then
    error "Installation root is not a directory: $target"; exit 1
  fi
done
for name in link.zsh slnk.zsh link_install.zsh slnk.conf slnk.conf.example README.md; do
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
for name in link.zsh slnk.zsh link_install.zsh README.md; do
  install_file "$root/$name" "$repo/$name" || exit 1
done
if [[ -e "$repo/slnk.conf" || -L "$repo/slnk.conf" ]]; then
  if [[ ! -f "$repo/slnk.conf" ]]; then error 'Existing slnk.conf is not a readable regular file.'; exit 1; fi
  print -r -- "Preserved configuration: $repo/slnk.conf"
  install_file "$root/slnk.conf" "$repo/slnk.conf.example" || exit 1
else
  install_file "$root/slnk.conf" "$repo/slnk.conf" || exit 1
fi
command chmod +x "$repo/link.zsh" "$repo/slnk.zsh" "$repo/link_install.zsh" || exit 1
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
if [[ -n $zshrc_input ]] && ! command cmp -s -- "$zshrc_input" "$zshrc"; then
  # Stage new contents without touching the symlink; preserve tracked file mode.
  stage=$(command mktemp "${zshrc:h}/.zshrc-stage.XXXXXXXX") || exit 1
  {
    command cp -p -- "$zshrc" "$stage" || exit 1
    command cat -- "$zshrc_input" > "$stage" || exit 1
    backup="$HOME/.zshrc.$stamp"; integer suffix=0
    while [[ -e $backup || -L $backup ]]; do
      (( suffix += 1 )); backup="$HOME/.zshrc.$stamp.$suffix"
    done
    # -n prevents overwriting any existing backup; verify the resulting copy.
    command cp -p -n -- "$zshrc" "$backup" || exit 1
    if [[ -L $backup ]] || ! command cmp -s -- "$zshrc" "$backup"; then
      error "Cannot verify .zshrc backup: $backup"; exit 1
    fi
    print -r -- "Backup: $backup"
    command mv -f -- "$stage" "$zshrc" || exit 1
    print -r -- "Updated tracked dotfile: $zshrc"
  } always {
    command rm -f -- "$stage"
  }
fi
print -r -- "Installed scripts in $repo and links in $links."
