# Moving a newline-inclusive selection to EOF must keep both endpoints in bounds.
cmd new_file
type a
key Return
type b
key ctrl+Home
key shift+Down
cmd move_line_down
print-doc
print-state
type X
print-doc
cmd undo
print-doc
cmd undo
print-doc
cmd redo
print-doc
cmd redo
print-doc
# The same selection made in reverse must stay valid.
cmd new_file
type a
key Return
type b
key Home
key shift+Up
cmd move_line_down
print-state
type X
print-doc
# Multiple lines, with a multibyte final line and no final newline.
cmd new_file
type a
key Return
type b
key Return
type β
key ctrl+Home
key shift+Down
key shift+Down
cmd move_line_down
print-state
type X
print-doc
# A following newline stays included in the selection when it exists.
cmd new_file
type a
key Return
type b
key Return
type c
key ctrl+Home
key shift+Down
cmd move_line_down
print-state
type X
print-doc
# Moving up retains the selection's separator before the displaced line.
cmd new_file
type a
key Return
type b
key Return
type c
key ctrl+Home
key Down
key shift+Down
cmd move_line_up
print-state
type X
print-doc
quit
