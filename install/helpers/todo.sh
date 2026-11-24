# Current desktop setup, shared by installation and reconciliation. Hyprland has
# no Monarch task-panel keybinding yet (documented gap in docs/fork-status.md);
# this only runs the package's own desktop setup.
monarch_configure_todo() {
  [[ -x /usr/bin/monarch-todo ]] || return 1
  /usr/bin/monarch-todo setup-desktop
}
