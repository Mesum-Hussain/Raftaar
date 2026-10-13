# right click keeps the selection; menu Copy, then paste elsewhere
open tests/data/words.txt
click 312 51
click 312 51
click 316 54 right
click 356 114
cmd new_file
key ctrl+v
print-doc
quit
