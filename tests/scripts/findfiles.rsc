# find in files opens at once and reads the project's files after its first frame: keys work while
# it reads, and once every file is read the query runs over all of them. Its word is its own:
# grep.rsc searches the whole repository for another one.
# start: tests/data/findfiles
key ctrl+shift+f
print-palette
type wombat
print-palette
wait-grep
print-palette
key Down
key Return
print-state
quit
