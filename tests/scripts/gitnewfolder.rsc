# git: a new folder's files each get a row in the Git panel (git ls-files --others), and a click shows
# that file's changes; the folder's ignored file stays out (tests/data/gitnewfolder.setup)
# start: @HOME@/repo
# the width the clicks and wrapped rows below were measured in
resize 1020 860
wait-git
cmd git_history
wait-git
# the folder's files are known already: the sidebar's count of the changes asked for them
print-scm
wait-git
print-scm
# the history counts the files the panel lists
print-gitlog
click 800 328
wait-git
print-state
print-doc
cmd git_history
click 800 300
wait-git
print-state
print-doc
quit
