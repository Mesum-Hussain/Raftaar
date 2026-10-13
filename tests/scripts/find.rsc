# find bar: incremental search, next/prev, replace all
open tests/data/words.txt
key ctrl+f
type eta
print-state
key Return
print-state
key shift+Return
print-state
key Escape
key ctrl+h
key Tab
type ETA
key ctrl+Return
key Escape
print-doc
key ctrl+z
print-doc
quit
