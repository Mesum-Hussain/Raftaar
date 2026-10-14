# Reopen Closed Tab: the last closed tab first, in its place, with its cursor and selection; Close All
# comes back one tab at a time, in order; the theme picker still opens
open README.md
open tests/data/words.txt
open tests/data/case.txt
cmd prev_tab
key Down
key Down
key Right
key shift+End
cmd close_tab
print-tabs
cmd reopen_closed_tab
print-tabs
print-state
cmd settings
cmd close_all_tabs
print-tabs
cmd reopen_closed_tab
cmd reopen_closed_tab
print-tabs
cmd reopen_closed_tab
cmd reopen_closed_tab
cmd reopen_closed_tab
print-tabs
cmd select_theme
print-state
quit
