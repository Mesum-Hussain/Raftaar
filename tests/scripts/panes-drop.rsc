# panes: a file dragged from the explorer onto an edge of a pane opens beside it, in a pane of its
# own; dragged again onto another edge, its pane moves there. A click (no drag) opens it as ever
# start: tests/data/findfiles
open tests/data/case.txt
move 100 122
wait 50
down
wait 50
move 110 132
wait 50
move 1300 300
wait 50
up
wait 200
print-tabs
print-state
move 100 122
wait 50
down
wait 50
move 110 132
wait 50
move 500 800
wait 50
up
wait 200
print-tabs
cmd close_tab
wait 100
print-tabs
click 100 122
wait 100
print-tabs
quit
