# Open Folder and the project menu: the window takes up another folder, asking about unsaved files
# first; each folder comes back with its last session. The menu lists the recent folders.
# start: @HOME@/work/alpha
open @HOME@/work/alpha/a.txt
type x
cmd open_folder
print-palette
type ../
print-palette
type b
print-palette
key Return
print-palette
key Return
print-state
key Escape
print-project
print-state
# the menu: the latest sessions' folders, but not this one or one that is gone; Esc closes it
cmd open_recent
print-menu
key Escape
print-menu
cmd open_recent
click 100 186
print-state
key Return
print-project
print-state
cmd open_recent
print-menu
click 100 158
print-project
print-state
print-doc
# a name that matches nothing leaves no row: Enter does not take up the folder above it
cmd open_folder
type zz
print-palette
key Return
print-project
key Escape
# Ctrl+Enter opens the selected folder instead of going into it
cmd open_folder
key BackSpace
key BackSpace
key BackSpace
key BackSpace
key BackSpace
key BackSpace
type ga
key ctrl+Return
print-project
print-state
quit
