# Mirror the Arch console keyboard layout (XKBLAYOUT / XKBVARIANT) into
# ~/.config/hypr/keyboard.conf, sourced by the Monarch Hyprland config after
# the defaults. Key bindings use keycodes for the number row, so Latin layouts
# such as AZERTY resolve workspace shortcuts without extra rules.
#
# Always (re)write the file so the result is idempotent; when no layout is
# configured it holds only a comment and the include still resolves.

vconsole="/etc/vconsole.conf"
target="$HOME/.config/hypr/keyboard.conf"
mkdir -p "$(dirname "$target")"

layout=""
variant=""
if [[ -r $vconsole ]]; then
  layout=$(grep '^XKBLAYOUT=' "$vconsole" 2>/dev/null | cut -d= -f2 | tr -d '"')
  variant=$(grep '^XKBVARIANT=' "$vconsole" 2>/dev/null | cut -d= -f2 | tr -d '"')
fi

{
  echo "# Generated from $vconsole by monarch detect-keyboard-layout."
  echo "# Override in ~/.config/hypr/input.conf."
  if [[ -n $layout ]]; then
    echo "input {"
    echo "  kb_layout = $layout"
    [[ -n $variant ]] && echo "  kb_variant = $variant"
    echo "}"
  fi
} >"$target"
