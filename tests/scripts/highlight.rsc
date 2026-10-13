# incremental re-highlighting after edits far above the viewport
open tests/data/lines.c
key ctrl+End
print-syntax 390
key ctrl+Home
type /*
key ctrl+End
print-syntax 390
key ctrl+Home
key Delete
key Delete
key ctrl+End
print-syntax 390
key ctrl+Home
type /*
key Return
key ctrl+End
print-syntax 390
key ctrl+z
key ctrl+z
key ctrl+End
print-syntax 390
quit
