# Toggle Comment where a comment counts only at a line's start (toggle_comment): HAML's -#, Batch's REM
cmd new_file
cmd select_language
type HAML
key Return
type %div
key Return
type %p hello
key ctrl+a
cmd toggle_comment
print-doc
cmd toggle_comment
print-doc
cmd new_file
cmd select_language
type Batch
key Return
type echo hi
cmd toggle_comment
print-doc
cmd toggle_comment
print-doc
quit
