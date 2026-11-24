-- Services and helpers launched at session start. The shell layer (bar,
-- launcher, notifications, lock, wallpaper, OSD, polkit agent) is started by
-- shell.lua, not here.
monarch.autostart("uwsm-app -- fcitx5 --disable notificationitem")
monarch.autostart("monarch-powerprofiles-set")
monarch.autostart("monarch-provision-first-run")

-- Slow app launch fix: export the session environment to systemd and D-Bus
monarch.autostart("systemctl --user import-environment $(env | cut -d'=' -f 1)")
monarch.autostart("dbus-update-activation-environment --systemd --all")

-- Run post-boot hooks after the startup config has loaded
monarch.autostart("sleep 2 && monarch-hook post-boot")
