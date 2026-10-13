cmd toggle_terminal
wait 800
type ./build.sh release && ls -l build/raftaar
key Return
wait 8000
type build/raftaar --version
key Return
wait 400
type git log --oneline -4
key Return
wait 800
shot @OUT@
quit
