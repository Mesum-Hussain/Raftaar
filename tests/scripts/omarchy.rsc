# Omarchy: followed until a theme is picked; switches live; unknown themes get raftaar's own, light or dark
print-state
open @HOME@/.local/state/omarchy/current/theme.name
key ctrl+a
type catppuccin
key ctrl+s
wait 20
print-state
key ctrl+a
type paper-cut
key ctrl+s
wait 20
print-state
cmd select_theme
type nord
key Return
key ctrl+a
type everforest
key ctrl+s
wait 20
print-state
cmd select_theme
type follow omarchy
key Return
print-state
quit
