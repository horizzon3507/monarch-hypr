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


monarch_reconcile_seeded_file \
  "$MONARCH_PATH/config/alacritty/monarch-text-size.toml" \
  "$HOME/.config/alacritty/monarch-text-size.toml"

# Daemon and lock-screen configs for the Hyprland shell. Seeded once so a first
# login has them; later edits are the user's and are never replaced
# (`monarch refresh shell` is the explicit reset).
for shell_config in hypr/hypridle.conf hypr/hyprlock.conf hypr/hyprpaper.conf \
  mako/config walker/config.toml swayosd/style.css; do
  monarch_reconcile_seeded_file \
    "$MONARCH_PATH/config/$shell_config" "$HOME/.config/$shell_config"
done

"$MONARCH_PATH/bin/monarch-state" clear-stale-restarts

for palette in "$MONARCH_PATH"/config/monarch/palettes/*.json; do
  monarch_reconcile_managed_file "$palette" \
    "$HOME/.config/monarch/palettes/$(basename "$palette")"
done

# Apply the current theme through the Hyprland shell.
monarch-theme-apply >/dev/null 2>&1 || true

# The optional todo package handles its own plugin activation and legacy copies.
monarch_reconcile_todo "$MONARCH_PATH"
monarch_reconcile_lazyvpn "$MONARCH_PATH"
monarch_reconcile_pentestenv "$MONARCH_PATH"
