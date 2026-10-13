# click, double click word, triple click line, drag selection, a click after a partial-line scroll
# without the explorer: its width follows the names in it
cmd toggle_sidebar
open tests/data/words.txt
click 71 51
print-state
click 71 51
click 71 51
print-state
click 71 51
print-state
move 64 72
down
move 179 93
up
print-state
type X
print-doc
# a click after scrolling part of a line lands on the line under the pointer
open tests/data/lines.c
scroll 40
click 159 264
print-state
wait 500
scroll 57
click 159 264
print-state
quit
