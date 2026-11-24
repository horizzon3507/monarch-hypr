# LazyVPN has no Hyprland bar item or keybinding yet (documented gap in
# docs/fork-status.md). Only the package desktop entry and legacy launcher cleanup stay.
monarch_configure_lazyvpn() {
  local config_dir=${XDG_CONFIG_HOME:-$HOME/.config} data_dir=${XDG_DATA_HOME:-$HOME/.local/share}
  local legacy

  /usr/bin/monarch-lazyvpn --preview --help >/dev/null 2>&1 || {
    echo "LazyVPN 0.2.0 or newer is required for graphical integration." >&2
    return 1
  }
  [[ -f /usr/share/applications/monarch-lazyvpn.desktop ]] || return 1

  legacy="$data_dir/applications/LazyVPN.desktop"
  if [[ -f $legacy ]] && grep -Fqx 'Exec=monarch-launch-floating-terminal-with-presentation monarch-lazyvpn' "$legacy"; then
    [[ -e $legacy.pre-gpui ]] || cp -p "$legacy" "$legacy.pre-gpui" || return
    rm -f "$legacy"
  fi
  mkdir -p "$config_dir/monarch-lazyvpn"
}
