-- Window rules. Later rules win. https://wiki.hypr.land/configuring/core/rules/window-rules/
local function rule(match, effects)
  effects.match = match
  hl.window_rule(effects)
end

rule({ class = ".*" }, { suppress_event = "maximize" })
-- Tag every window for default opacity; apps opt out by removing the tag.
rule({ class = ".*" }, { tag = "+default-opacity" })
-- Fix some dragging issues with XWayland
rule({ class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false }, { no_focus = true })

-- Terminals
rule({ class = "(Alacritty|kitty|com.mitchellh.ghostty|foot)" }, { tag = "+terminal" })
rule({ tag = "terminal" }, { tag = "-default-opacity" })
rule({ tag = "terminal" }, { opacity = "0.97 0.9" })

-- Browsers: subtle opacity change, never on video sites
rule({ class = "((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)" }, { tag = "+chromium-based-browser" })
rule({ class = "([fF]irefox|zen|librewolf)" }, { tag = "+firefox-based-browser" })
rule({ tag = "chromium-based-browser" }, { tag = "-default-opacity" })
rule({ tag = "firefox-based-browser" }, { tag = "-default-opacity" })
rule({ class = "(chrome-youtube.com__-Default|chrome-app.zoom.us__wc_home-Default)" }, { tag = "-chromium-based-browser" })
rule({ class = "(chrome-youtube.com__-Default|chrome-app.zoom.us__wc_home-Default)" }, { tag = "-default-opacity" })
-- Force chromium-based browsers into a tile to deal with the --app bug
rule({ tag = "chromium-based-browser" }, { tile = true })
rule({ tag = "chromium-based-browser" }, { opacity = "1.0 0.97" })
rule({ tag = "firefox-based-browser" }, { opacity = "1.0 0.97" })

-- Hide the screen-sharing notification bar
rule({ title = ".*is sharing.*" }, { workspace = "special silent" })

-- Monarch's own tools open as floating windows of a known size
rule({ class = "org.monarch.(update|agent-usage|pentest|about)" }, { float = true, center = true })
rule({ class = "org.monarch.(update|agent-usage|pentest)" }, { size = "875 600" })
rule({ class = "org.monarch.about" }, { size = "1100 700" })
rule({ class = "org.monarch.CrashReport(.Preview)?" }, { float = true, center = true, size = "900 600" })
rule({ class = "disktree" }, { float = true, center = true, size = "1000 650" })
rule({ class = "at.yrlf.wl_mirror" }, { float = true, tag = "-default-opacity", opacity = "1 1" })

-- Floating windows
rule({ tag = "floating-window" }, { float = true, center = true, size = "875 600" })
rule({ class = "(org.monarch.nmtui|org.monarch.wiremix|org.monarch.btop|org.monarch.terminal|org.monarch.bash|org.codeberg.dnkl.foot|org.gnome.NautilusPreviewer|org.gnome.Evince|com.gabm.satty|Monarch|About|TUI.float|imv|mpv)" }, { tag = "+floating-window" })
rule({ class = "(xdg-desktop-portal-gtk|sublime_text|DesktopEditors|org.gnome.Nautilus)", title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)" }, { tag = "+floating-window" })
rule({ class = "org.gnome.Calculator" }, { float = true })

-- Fullscreen screensaver
rule({ class = "org.monarch.screensaver" }, { fullscreen = true, float = true, animation = "slide" })

-- No transparency on media windows
rule({ class = "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$" }, { tag = "-default-opacity" })

-- Popped window rounding, and no idle while a `noidle` window is open
rule({ tag = "pop" }, { rounding = 8 })
rule({ tag = "noidle" }, { idle_inhibit = "always" })

-- Picture-in-picture overlays
rule({ title = "(Picture.?in.?[Pp]icture)" }, { tag = "+pip" })
rule({ tag = "pip" }, {
  tag = "-default-opacity", float = true, pin = true, size = "600 338",
  keep_aspect_ratio = true, border_size = 0, opacity = "1 1", move = "100%-w-40 4%",
})

-- Default opacity, applied after the app rules have had a chance to opt out
rule({ tag = "default-opacity" }, { opacity = "0.97 0.9" })

-- Hide chat windows from screen capture. On by default; the flag file written
-- by `monarch toggle chat-privacy-off` turns it off at the next reload.
local flag = io.open(os.getenv("HOME") .. "/.local/state/monarch/toggles/chat-privacy-off", "r")
if flag then
  flag:close()
else
  monarch.default("chat-privacy")
end
