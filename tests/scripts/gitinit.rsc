# source control in a repository without commits (tests/data/gitinit.setup): the work tree row alone,
# Enter on it goes to the message, Ctrl+Enter makes the first commit
open @HOME@/repo
wait-git
cmd git_history
wait-git
print-gitlog
print-scm
key Return
print-state
type First
key Escape
# what scrolled out of the panel takes no clicks: here Commit All is under the tab strip
resize 1400 260
move 850 200
scroll 600
click 850 50
wait-git
print-state
print-scm
resize 1400 860
key Return
key ctrl+Return
wait-git
print-git
print-gitlog
print-scm
