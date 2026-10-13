# git: status, change marks, diff views, history, refresh after a commit, the setting
# start: @HOME@/repo
# the width the clicks and wrapped rows below were measured in
resize 1020 860
wait-git
print-git
open @HOME@/repo/a.txt
wait-git
print-git
key ctrl+End
key Return
type eight
print-git
key ctrl+z
key ctrl+z
print-git
key ctrl+Home
key ctrl+shift+k
print-git
open @HOME@/repo/crlf.txt
wait-git
print-git
# changes of the file against HEAD; the view is read-only
cmd git_changes
wait-git
print-state
print-doc
type x
key BackSpace
key ctrl+shift+k
print-state
# history: graph, the files of a commit, a commit's diff
cmd git_history
wait-git
print-state
print-gitlog
key Down
key Down
key Down
key Down
wait-git
print-gitlog
click 780 190
wait-git
print-state
print-doc
# a commit from the terminal: status, marks and history follow
cmd toggle_terminal
wait-term $
type git commit -qam 'Commit all' && printf 'commit %s\n' done
key Return
wait-term commit done
wait 300
wait-git
print-git
print-gitlog
cmd toggle_terminal
# past the terminal's tab, which opened after the diff's
key ctrl+Tab
key ctrl+Tab
key ctrl+Tab
print-state
print-git
# turning git off in the config file
cmd open_config
key ctrl+End
key Return
type [git]
key Return
type enabled = false
key Return
key ctrl+s
wait-git
print-git
