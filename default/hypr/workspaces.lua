-- Ten persistent workspaces, so the bar always shows 1-10.
for index = 1, 10 do
  hl.workspace_rule({ workspace = tostring(index), persistent = true, default = (index == 1) })
end
