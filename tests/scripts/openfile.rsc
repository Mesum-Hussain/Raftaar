# Open File: a browser from the project folder. Enter goes into a folder, Backspace past a / goes up,
# hidden entries need a leading dot, Tab takes a name; a file outside the project opens in a tab
# start: @HOME@/work/alpha
cmd open_file
print-palette
type s
print-palette
key Return
print-palette
key Return
print-state
cmd open_file
type .
print-palette
key BackSpace
key BackSpace
print-palette
key ctrl+a
type ~/no
print-palette
key Tab
print-palette
key Return
print-state
print-project
# from the project menu
cmd open_recent
print-menu
click 100 128
print-palette
key Escape
print-palette
# a pipe is not opened: that would wait for a writer
open @HOME@/pipe
print-state
quit
