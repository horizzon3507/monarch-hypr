# Migrate legacy Noctalia terminal theme references in existing user configs
# to the Monarch-rendered theme files (~/.config/monarch/current/theme/).
#
# Fresh installs and monarch-install-terminal already ship the new references;
# this covers users provisioned before that fix. Safety rules:
#   - only exact, full-line matches of the shipped legacy defaults are changed
#   - a reference is only rewritten when the legacy theme file it points at is
#     missing, i.e. the reference is actually broken; a user who placed their
#     own theme at the legacy path keeps their working setup untouched
#   - the original file is preserved next to it as
#     <file>.monarch-backup.XXXXXX before any edit (limine-kernel-order.sh
#     convention)
#   - idempotent: once migrated (or never matched), later runs change nothing
#
# Sourced by install/reconcile/user.sh; call terminal_themes_migrate.

# $1 config file, $2 legacy exact line, $3 replacement (may be multi-line),
# $4 legacy theme target whose existence means "leave it alone",
# $5 optional second legacy exact line (legacy comment) to also replace.
terminal_themes_migrate_line() {
  local file=$1 legacy=$2 replacement=$3 legacy_target=$4 legacy_extra=${5:-}
  [[ -f $file ]] || return 0
  grep -qxF "$legacy" "$file" || return 0
  [[ -e $legacy_target || -L $legacy_target ]] && return 0

  local backup tmp
  backup=$(mktemp "${file}.monarch-backup.XXXXXX") || return 1
  cp --preserve=all -- "$file" "$backup" || { rm -f -- "$backup"; return 1; }
  tmp=$(mktemp "${file}.monarch-migrate.XXXXXX") || { rm -f -- "$backup"; return 1; }

  awk -v legacy="$legacy" -v repl="$replacement" -v legacy_extra="$legacy_extra" '
    legacy_extra != "" && $0 == legacy_extra { next }
    $0 == legacy { printf "%s\n", repl; next }
    { print }
  ' "$file" >"$tmp" || { rm -f -- "$tmp"; return 1; }

  if cmp -s "$file" "$tmp"; then
    rm -f -- "$tmp" "$backup"
    return 0
  fi
  chmod --reference="$backup" "$tmp"
  mv -f -- "$tmp" "$file" || { rm -f -- "$tmp"; return 1; }
  echo "Migrated legacy Noctalia theme reference in $file (backup: $backup)" >&2
}

# Seed the theme symlink an existing install is missing. Never overwrites:
# an existing file, directory or link at $2 is left alone.
terminal_themes_seed_link() {
  local app_dir=$1 link=$2 target=$3
  [[ -d $app_dir ]] || return 0
  [[ -e $link || -L $link ]] && return 0
  mkdir -p -- "$(dirname "$link")" || return 1
  ln -s -- "$target" "$link" || return 1
  echo "Seeded $link -> $target" >&2
}

terminal_themes_migrate() {
  local cfg="$HOME/.config"

  terminal_themes_migrate_line "$cfg/foot/foot.ini" \
    'include=~/.config/foot/themes/noctalia' \
    '# Rendered by monarch-theme-render from the active Monarch palette.
include=~/.config/monarch/current/theme/foot.ini' \
    "$cfg/foot/themes/noctalia"

  terminal_themes_migrate_line "$cfg/kitty/kitty.conf" \
    'include themes/noctalia.conf' \
    '# Rendered by monarch-theme-render from the active Monarch palette.
include ../monarch/current/theme/kitty.conf' \
    "$cfg/kitty/themes/noctalia.conf"

  terminal_themes_migrate_line "$cfg/alacritty/alacritty.toml" \
    '  "~/.config/alacritty/themes/noctalia.toml",' \
    '  "~/.config/monarch/current/theme/alacritty.toml",' \
    "$cfg/alacritty/themes/noctalia.toml"

  terminal_themes_migrate_line "$cfg/ghostty/config" \
    'theme = noctalia' \
    '# Rendered by monarch-theme-render from the active Monarch palette;
# themes/monarch-current links to the rendered file.
theme = monarch-current' \
    "$cfg/ghostty/themes/noctalia" \
    '# Dynamic theme colors (Noctalia)'
  terminal_themes_seed_link "$cfg/ghostty" \
    "$cfg/ghostty/themes/monarch-current" \
    "../../monarch/current/theme/ghostty.conf"

  terminal_themes_migrate_line "$cfg/btop/btop.conf" \
    'color_theme = "noctalia"' \
    '# Rendered by monarch-theme-render from the active Monarch palette;
# themes/monarch-current.theme links to the rendered file.
color_theme = "monarch-current"' \
    "$cfg/btop/themes/noctalia.theme"
  terminal_themes_seed_link "$cfg/btop" \
    "$cfg/btop/themes/monarch-current.theme" \
    "../../monarch/current/theme/btop.theme"
}
