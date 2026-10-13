# soft wrap: rows, vertical motion by row, clicks and selection on wrapped rows
# the width the clicks and wrapped rows below were measured in
# without the explorer: its width follows the names in it
cmd toggle_sidebar
resize 779 860
open tests/data/prose.md
# as its text: a Markdown file opens as a page
cmd toggle_markdown_preview
cmd toggle_word_wrap
key Down
key Down
key Down
print-state
key Down
key Down
print-state
click 259 114
print-state
key shift+Down
key shift+Down
print-state
key Escape
click 459 344
print-state
type Q
print-state
key ctrl+z
key ctrl+End
key Up
key Up
print-state
key ctrl+Home
key PageDown
print-state
cmd toggle_word_wrap
key Down
print-state
quit
