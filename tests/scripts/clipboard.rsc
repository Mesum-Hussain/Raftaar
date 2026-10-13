# Whole-line metadata must only apply to the actual text copied from the editor.
cmd new_file
type abc
key Home
key Right
cmd copy
cmd find
key ctrl+a
type WXYZ
key ctrl+a
key ctrl+c
key Escape
cmd paste
print-doc
cmd undo
print-doc
# Different-length text copied from a field remains ordinary text as well.
cmd find
key ctrl+a
type XY
key ctrl+a
key ctrl+c
key Escape
cmd paste
print-doc
cmd undo
# An unchanged whole-line clipboard still pastes above the current line.
cmd copy
cmd paste
print-doc
cmd undo
print-doc
quit
