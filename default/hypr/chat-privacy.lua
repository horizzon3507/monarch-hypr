-- Rules that hide chat windows from screen capture (see rules.lua).
local function hide(match)
  hl.window_rule({ match = match, no_screen_share = true })
end

hide({ class = "(?i)(^|[._-])(beeper(texts)?|discord|vesktop|teams([_-]for[_-]linux)?|whatsapp)([._-]|$)" })
hide({ class = "(?i)(^|[._-])(signal(-desktop)?|telegram(-desktop)?|element(-desktop)?|riot)([._-]|$)" })
hide({ class = "(?i)(^|[._-])(slack|mattermost(-desktop)?|zulip(-desktop)?|ferdium|rambox|franz)([._-]|$)" })
hide({ title = "(^Teams$|Microsoft Teams)" })
hide({
  class = "(?i)(^|[._-])(chromium|chrome|brave|edge|opera|vivaldi|helium)([._-]|$)",
  title = "(?i)^(\\([0-9]+\\) )?(WhatsApp( Web)?|Messenger|Google Chat|Slack|Discord)( - .+)?$",
})
