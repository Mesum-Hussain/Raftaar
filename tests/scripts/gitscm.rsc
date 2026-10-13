# source control: fetch, pull, stage, unstage, discard, commit, sync into a merge conflict, amend, push,
# discard all, publish; the remote is a folder next to the repository (tests/data/gitscm.setup)
# the width the clicks and wrapped rows below were measured in
resize 1020 860
open @HOME@/repo
wait-git
cmd git_history
wait-git
print-git
print-scm
# fetch: the remote's commit; pulling it stops at the local change to the same file
cmd git_fetch
wait-git
print-git
cmd git_pull
wait-git
print-scm
# a file's box stages it, and unstages it (the error goes with the next command)
click 997 372
wait-git
print-scm
click 997 300
wait-git
print-scm
# discarding a new file deletes it, after asking
click 970 328
print-state
key Return
wait-git
print-scm
# the message: Enter breaks the line, Ctrl+Enter commits every change, as none is staged
click 850 110
type Say uno
key Return
key Return
type In Spanish.
print-scm
key ctrl+Return
wait-git
print-scm
print-git
# Sync Changes: the pull merges and stops at the conflict; the merge's message fills the box
click 790 224
wait-git
print-scm
# resolved in the editor, staged, committed with that message
open @HOME@/repo/a.txt
key ctrl+a
type uno y ONE
key Return
type two
key Return
type three
key Return
key ctrl+s
wait-git
cmd git_history
wait-git
cmd git_stage_all
wait-git
print-scm
# Unstage All keeps the merge going
cmd git_unstage_all
wait-git
print-scm
cmd git_stage_all
wait-git
cmd git_commit
wait-git
print-gitlog
# amending takes the message box's text
click 850 110
type Merge the remote
cmd git_commit_amend
wait-git
print-gitlog
print-git
# Push
click 935 224
wait-git
print-git
print-scm
# a commit without a message goes to the message box; Esc leaves it
open @HOME@/repo/a.txt
key ctrl+End
type !
key ctrl+s
wait-git
cmd git_commit
print-state
key Escape
print-state
# Discard All, after asking; the open file follows
cmd git_discard_all
print-state
key Return
wait-git
wait 300
print-scm
open @HOME@/repo/a.txt
print-doc
# a branch made in the terminal has no upstream: Publish Branch
cmd git_history
cmd toggle_terminal
wait 300
type git checkout -q -b topic
key Return
wait 1500
wait-git
cmd toggle_terminal
wait-git
print-git
print-scm
click 790 224
wait-git
print-git
print-scm
