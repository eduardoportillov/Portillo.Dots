# shellcheck shell=bash
# Load the per-host OpenCode provider credentials referenced by {env:NAME}.
#
# The generated opencode.jsonc never contains credential values; this file is
# what supplies them at runtime. It is deliberately strict about what it will
# source: never a symlink, never another owner's file, never group/world
# readable. Delete ~/.config/opencode/secrets.env to opt out entirely.
#
# Works when sourced from Bash or Zsh.

_portillo_secrets="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/secrets.env"
if [ -f "$_portillo_secrets" ] && [ ! -L "$_portillo_secrets" ] && [ -O "$_portillo_secrets" ]; then
  if [ -r "$_portillo_secrets" ]; then
    _portillo_mode="$(stat -c '%a' "$_portillo_secrets" 2>/dev/null || stat -f '%Lp' "$_portillo_secrets" 2>/dev/null || echo '')"
    case "$_portillo_mode" in
      000|200|400|600)
        # shellcheck disable=SC1090
        . "$_portillo_secrets"
        ;;
      *)
        printf '[WARN] Not sourcing %s: expected mode 0600, found %s\n' "$_portillo_secrets" "$_portillo_mode" >&2
        ;;
    esac
    unset _portillo_mode
  fi
else
  # Missing is normal: the base/server profiles carry no provider credentials.
  if [ -e "$_portillo_secrets" ]; then
    printf '[WARN] Ignoring %s: not a plain file owned by this user\n' "$_portillo_secrets" >&2
  fi
fi
unset _portillo_secrets
