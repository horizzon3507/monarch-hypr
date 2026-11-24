set -euo pipefail

echo "Reconcile Monarch user state"

systemctl --user daemon-reload

# Match config/uwsm/env without loading keys or replacing custom agent settings.
systemctl --user enable --now ssh-agent.socket
systemctl --user enable --now monarch-screencast-dnd.service
systemctl --user try-restart monarch-crash-watch.service

source "$MONARCH_PATH/install/reconcile/config-files.sh"
bash "$MONARCH_PATH/install/reconcile/disktree-user.sh"
python3 -I "$MONARCH_PATH/install/reconcile/exegol.py" "$MONARCH_PATH" "$HOME"
source "$MONARCH_PATH/install/reconcile/about-branding.sh"
source "$MONARCH_PATH/install/reconcile/todo.sh"
source "$MONARCH_PATH/install/reconcile/lazyvpn.sh"
source "$MONARCH_PATH/install/reconcile/pentestenv.sh"
source "$MONARCH_PATH/install/reconcile/chromium-flags.sh"
source "$MONARCH_PATH/install/reconcile/mise.sh"
source "$MONARCH_PATH/install/reconcile/nvidia-env.sh"
monarch_reconcile_nvidia_environment

source "$MONARCH_PATH/install/reconcile/chat-privacy.sh"

monarch_reconcile_seeded_file \
  "$MONARCH_PATH/config/alacritty/monarch-text-size.toml" \
  "$HOME/.config/alacritty/monarch-text-size.toml"

"$MONARCH_PATH/bin/monarch-state" clear-stale-restarts

# Palettes are managed; shell configs are seeded so user edits survive upgrades.
for palette in "$MONARCH_PATH"/config/monarch/palettes/*.json; do
  monarch_reconcile_managed_file "$palette" \
    "$HOME/.config/monarch/palettes/$(basename "$palette")"
done

for shell_config in \
  waybar/config.jsonc waybar/style.css mako/config walker/config.toml \
  swayosd/style.css hypr/hyprlock.conf hypr/hypridle.conf hypr/hyprpaper.conf; do
  monarch_reconcile_seeded_file \
    "$MONARCH_PATH/config/$shell_config" "$HOME/.config/$shell_config"
done

# Render the active theme so every shell component has its color files.
monarch-theme-render >/dev/null 2>&1 || true

# The optional todo package handles its own plugin activation and legacy copies.
monarch_reconcile_todo "$MONARCH_PATH"
monarch_reconcile_lazyvpn "$MONARCH_PATH"
monarch_reconcile_pentestenv "$MONARCH_PATH"
