# find in files: smart case, opening a result selects the match, selection as the query;
# wait-grep stands for the frames in which it reads the project's files
key ctrl+shift+f
wait-grep
type quokka
key Down
key Return
print-state
key ctrl+shift+f
wait-grep
key Return
print-state
key ctrl+shift+f
wait-grep
type Quokka
key Return
print-state
key ctrl+shift+f
wait-grep
type zzq
type qzz
key Return
print-state
key Escape
quit
