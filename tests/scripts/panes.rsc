# panes: Ctrl+Right and Ctrl+Down split the active pane with a new terminal, from a file as from a
# terminal; Ctrl+T opens one in a tab of its own. The tabs of the title bar are groups of panes:
# Previous Tab comes back to the pane that had the keys, and a pane closed leaves them to its neighbor
open tests/data/case.txt
key ctrl+Right
wait 400
print-tabs
key ctrl+Down
wait 400
print-tabs
key ctrl+t
wait 400
print-tabs
cmd prev_tab
print-tabs
cmd close_tab
wait 100
print-tabs
cmd close_tab
wait 100
print-tabs
print-state
quit
