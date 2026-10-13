# vim mode: motions, operators, text objects, visual mode, put, undo, ".", search, the : line
# without the explorer: its width follows the names in it
cmd toggle_sidebar
open tests/data/vim.c
print-state
cmd toggle_vim
print-state
# motions
type jw
print-state
type e
print-state
type fb;
print-state
type $
print-state
type 0
print-state
type }
print-state
type {
print-state
type G
print-state
type gg%
print-state
# operators with motions, counts, undo
type 2Gwdw
print-doc
type u
type d2w
print-doc
type u
type $bdw
print-doc
type u
type 3Gdd
print-doc
type p
print-doc
type u
type u
key ctrl+r
key ctrl+r
print-doc
print-state
type uu
# change, insert, count, "."
type 2Gwcwbar
key Escape
print-doc
print-state
type j.
print-doc
type uu
type gg3ihi
key Escape
print-doc
type j.
print-doc
type u
type u
type Aend
key ctrl+[
type j.
print-doc
type uu
type ggoNEW
key Escape
type 2.
print-doc
print-state
type uu
# text objects
type 2Gfzci"x
key Escape
print-doc
type da"
print-doc
type uu
type 2Gfbdi(
print-doc
type u
type 2Gfbda(
print-doc
type u
type 2Gci{
print-state
key Escape
print-doc
type u
type 2Gwdiw
print-doc
type u
type 2Gwdaw
print-doc
type u
# single keys
type gg2x
print-doc
type rZ
print-doc
type 3~
print-doc
type g~~
print-doc
type ggJ
print-doc
print-state
type uuuuu
type 2G$X
print-doc
type 0wD
print-doc
type k0sX
key Escape
print-doc
type jSnew
key Escape
print-doc
type uuuu
type 2G>>
type j.
print-doc
type <<
print-doc
type uuu
# visual mode
type ggvee
print-state
type d
print-doc
type u
type 2GVjd
print-doc
type u
type ggvjo
print-state
key Escape
type 2Gwvi(
print-state
type U
print-doc
type u
type ggVjJ
print-doc
type u
type 2GVj2>
print-doc
type u
# yank and put
type ggyyjp
print-doc
type u
type 2GwyiwwwPp
print-doc
type uu
type 3Gyy2Gwviwp
print-doc
type u
type 2GwwVp
print-doc
type u
type ggxp
print-doc
type uu
# search, on the command line
type /ba
print-state
key Return
print-state
type n
print-state
type N
print-state
type ?in
key Return
print-state
type /
key Return
print-state
type /qu
key Escape
print-state
type /zzz
key Return
print-state
type gg*
print-state
key Escape
# the : line, in the status bar
type :3
print-state
key Return
print-state
type :$
key Return
print-state
type :x
key BackSpace
key BackSpace
print-state
type :bogus
key Escape
print-state
# as in Vim: . after a visual change, / as a motion, a count after the operator, Esc after o,
# dw at a line end, d over whole lines, aw after an indentation, ~ on letters outside ASCII
type 2GVj>.
print-doc
type uu
type 2Gd/baz
key Return
print-doc
type u
type 6Gd1w.
print-doc
type uu
type 2Go
key Escape
print-doc
type u
type 6G$bdw
print-doc
type u
type 6G2D
print-doc
type u
type 2G^daw
print-doc
type u
type 6Gié
key Escape
type ~
print-doc
type uu
# * finds whole words, also after a / that was given up; the find bar finds any text
type Gofoo foobar foo
key Escape
type 0*
print-state
type 0l
cmd find
key Return
print-state
key Escape
key Escape
type 0*/bar
key Escape
type 0n
print-state
type u
# mouse: a drag is a visual selection, a click ends it
click 189 72
print-state
move 89 72
down
move 179 93
up
print-state
click 259 114
print-state
# insert mode keys stay the editor's; turning vim off
type i
key Return
key Escape
print-doc
print-state
cmd toggle_vim
type x
print-doc
print-state
quit
