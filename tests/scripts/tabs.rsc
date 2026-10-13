# closing tabs from the strip: middle click, then the last one with its close button
cmd settings
open tests/data/words.txt
open README.md
click 100 20 middle
print-state
click 100 20 middle
print-state
click 153 20
print-state
cmd new_file
print-state
quit
