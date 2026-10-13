# find bar ignoring case beyond ASCII: accented Latin, Greek (final sigma too), Cyrillic whose cases
# start with different bytes; Aa keeps case; Replace and Replace All take every case
# the width the clicks and wrapped rows below were measured in
resize 1020 860
open tests/data/case.txt
key ctrl+f
type été
print-state
key Return
print-state
key Return
print-state
key Return
print-state
# Aa: only the same case
click 883 71
key Return
print-state
key Return
print-state
click 883 71
key ctrl+a
type ΑΛΦΑ
print-state
key Return
print-state
key ctrl+a
type яблоко
print-state
key Return
print-state
key ctrl+a
type οδοσ
print-state
key Return
print-state
key Escape
# replace one, then all, in every case
key ctrl+Home
key ctrl+h
key ctrl+a
type ÉTÉ
key Tab
key ctrl+a
type summer
key Return
key Return
key Escape
print-doc
key ctrl+h
key ctrl+a
type ПРИВЕТ
key Tab
key ctrl+a
type hi
key ctrl+Return
key Escape
print-doc
key ctrl+z
key ctrl+z
key ctrl+z
print-doc
quit
