#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${1:-$SCRIPT_DIR/../zsh/.dircolors}"

if [[ ! -f "$SOURCE" ]]; then
  printf 'ERROR: dircolors source not found: %s\n' "$SOURCE" >&2
  exit 1
fi

ls_code() {
  case "$1" in
    NORMAL|NORM)                 printf 'no' ;;
    FILE)                        printf 'fi' ;;
    RESET)                       printf 'rs' ;;
    DIR)                         printf 'di' ;;
    LINK|LNK|SYMLINK)            printf 'ln' ;;
    MULTIHARDLINK)               printf 'mh' ;;
    FIFO|PIPE)                   printf 'pi' ;;
    SOCK)                        printf 'so' ;;
    DOOR)                        printf 'do' ;;
    BLK|BLOCK)                   printf 'bd' ;;
    CHR|CHAR)                    printf 'cd' ;;
    ORPHAN)                      printf 'or' ;;
    MISSING)                     printf 'mi' ;;
    SETUID|SUID)                 printf 'su' ;;
    SETGID|SGID)                 printf 'sg' ;;
    CAPABILITY)                  printf 'ca' ;;
    STICKY_OTHER_WRITABLE|OWT)   printf 'tw' ;;
    OTHER_WRITABLE|OWR)          printf 'ow' ;;
    STICKY)                      printf 'st' ;;
    EXEC)                        printf 'ex' ;;
    *) return 1 ;;
  esac
}

colors=""
while IFS= read -r raw || [[ -n "$raw" ]]; do
  read -r key value _ <<< "$raw"
  [[ -z "${key:-}" || -z "${value:-}" ]] && continue
  [[ "$key" == \#* ]] && continue

  case "$key" in
    TERM|COLORTERM|COLOR|OPTIONS|EIGHTBIT) continue ;;
  esac

  if [[ ! "$key" =~ ^[A-Za-z0-9_.*~#-]+$ ]] \
    || { [[ "$value" != "target" ]] && [[ ! "$value" =~ ^[0-9]+(\;[0-9]+)*$ ]]; }; then
    printf 'ERROR: unsafe dircolors entry: %s %s\n' "$key" "$value" >&2
    exit 1
  fi

  case "$key" in
    .*) entry="*${key}=${value}" ;;
    \**) entry="${key}=${value}" ;;
    *)
      code="$(ls_code "${key^^}")" || {
        printf 'ERROR: unsupported dircolors keyword: %s\n' "$key" >&2
        exit 1
      }
      entry="${code}=${value}"
      ;;
  esac

  colors+="${entry}:"
done < "$SOURCE"

read -r checksum size _ < <(cat "$SOURCE" "$0" | cksum)
printf "PORTILLO_DIRCOLORS_VERSION='%s-%s'\n" "$checksum" "$size"
printf 'export PORTILLO_DIRCOLORS_VERSION\n'
printf 'LS_COLORS=%q\n' "$colors"
printf 'export LS_COLORS\n'
