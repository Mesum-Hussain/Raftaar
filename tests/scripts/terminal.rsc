# terminals in tabs: a shell, colors, back to the file and to the terminal again, a second one, exit
open tests/data/case.txt
cmd toggle_terminal
wait 400
print-state
type printf 'a\033[31mb\033[0mc\n'
key Return
wait 400
print-term
cmd toggle_terminal
print-state
cmd toggle_terminal
print-state
cmd new_terminal
wait 300
print-state
type exit
key Return
wait 400
print-state
type exit
key Return
wait 400
print-state
