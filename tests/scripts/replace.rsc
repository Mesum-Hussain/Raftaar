# Replace All across an interior gap, grow/shrink, Unicode, and one-step undo/redo.
cmd new_file
type aaaaa a βa
key Home
key Right
key Right
type z
key BackSpace
key ctrl+h
key ctrl+a
type aa
key Tab
key ctrl+a
type xyz
key ctrl+Return
key Escape
print-doc
key ctrl+z
print-doc
key ctrl+shift+z
print-doc
# A replacement containing the needle is not searched again.
key ctrl+a
type a a
key ctrl+h
key ctrl+a
type a
key Tab
key ctrl+a
type aa
key ctrl+Return
key Escape
print-doc
key ctrl+z
print-doc
# Empty replacement, including matches on both sides of a newline.
key ctrl+a
type βaβa
key Return
type βa
key ctrl+h
key ctrl+a
type βa
key Tab
key ctrl+a
key BackSpace
key ctrl+Return
key Escape
print-doc
key ctrl+z
print-doc
key ctrl+shift+z
print-doc
# Empty query and absent query leave the document alone.
key ctrl+h
key ctrl+a
key BackSpace
key Tab
type x
key ctrl+Return
key Escape
print-doc
key ctrl+h
key ctrl+a
type absent
key Tab
key ctrl+Return
key Escape
print-doc
quit
