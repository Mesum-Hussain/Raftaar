# Next Pane (Ctrl+Shift+Tab): the panes of the active tab, clockwise around its middle; a tab with
# one view stays as it is
open tests/data/case.txt
key ctrl+Right
wait 400
key ctrl+Down
wait 400
print-tabs
key ctrl+shift+Tab
print-tabs
key ctrl+shift+Tab
print-tabs
key ctrl+shift+Tab
print-tabs
key ctrl+t
wait 400
print-tabs
key ctrl+shift+Tab
print-tabs
quit
