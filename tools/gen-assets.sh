#!/bin/sh
# emits build/assets.s: embedded fonts, themes and syntax files
cd "$(dirname "$0")/.."
emit() { # label file
    printf '.globl %s, %s_end\n.p2align 4\n%s: .incbin "%s"\n%s_end: .byte 0\n' "$1" "$1" "$1" "$PWD/$2" "$1"
}
echo '.section .rodata'
emit commit_ai_script runtime/ai/commit.sh
# one font for the interface and the code
emit font_mono assets/fonts/IosevkaFixed-Regular.ttf
printf '.globl font_ui, font_ui_end\n.set font_ui, font_mono\n.set font_ui_end, font_mono_end\n' 
# name table of runtime files: (name ptr, data ptr, data end); a grammar's entry also has its name,
# files, first_line and icon, for syntax_load_all to register it without parsing
for kind in themes syntax; do
    list=$(ls runtime/$kind 2>/dev/null | LC_ALL=C sort)
    i=0
    for f in $list; do
        emit "${kind}_$i" "runtime/$kind/$f"
        printf '%s_%d_name: .asciz "%s"\n' "$kind" $i "$f"
        i=$((i+1))
    done
    if [ $kind = syntax ] && [ $i -gt 0 ]; then
        # as the grammar parser reads them (key = value, blanks trimmed, the last one wins); bytes
        # other than letters, digits, space and . * _ / + - as octal escapes
        (cd runtime/syntax && LC_ALL=C awk '
        BEGIN { for (c = 1; c < 256; c++) ord[sprintf("%c", c)] = c }
        function esc(s,   r, i, ch) {
            r = ""
            for (i = 1; i <= length(s); i++) {
                ch = substr(s, i, 1)
                if (ch ~ /[A-Za-z0-9.*_\/+ -]/) r = r ch; else r = r sprintf("\\%03o", ord[ch])
            }
            return r
        }
        function flush() {
            if (f == "") return
            printf "syntax_%d_gname: .asciz \"%s\"\n", n, esc(v["name"])
            printf "syntax_%d_gfiles: .asciz \"%s\"\n", n, esc(v["files"])
            printf "syntax_%d_gfirst: .asciz \"%s\"\n", n, esc(v["first_line"])
            printf "syntax_%d_gicon: .asciz \"%s\"\n", n, esc(v["icon"])
            n++
        }
        FNR == 1 { flush(); f = FILENAME; split("", v) }
        {
            eq = index($0, "=")
            if (eq == 0) next
            key = substr($0, 1, eq - 1); gsub(/^[ \t\r]+|[ \t\r]+$/, "", key)
            if (key != "name" && key != "files" && key != "first_line" && key != "icon") next
            val = substr($0, eq + 1); gsub(/^[ \t\r]+|[ \t\r]+$/, "", val)
            v[key] = val
        }
        END { flush() }' $list)
    fi
    printf '.p2align 3\n.globl %s_table, %s_count\n%s_count: .quad %d\n%s_table:\n' $kind $kind $kind $i $kind
    j=0
    while [ $j -lt $i ]; do
        if [ $kind = syntax ]; then
            printf '.quad syntax_%d_name, syntax_%d, syntax_%d_end, syntax_%d_gname, syntax_%d_gfiles, syntax_%d_gfirst, syntax_%d_gicon\n' $j $j $j $j $j $j $j
        else
            printf '.quad %s_%d_name, %s_%d, %s_%d_end\n' $kind $j $kind $j $kind $j
        fi
        j=$((j+1))
    done
done
# the version (VERSION) and whether this is a release build (RAFTAAR_DIST=1, set by the release workflow)
dist=0
[ "${RAFTAAR_DIST:-}" = 1 ] && dist=1
printf '.globl raftaar_version, raftaar_dist\nraftaar_version: .asciz "%s"\n.p2align 2\nraftaar_dist: .long %d\n' "$(cat VERSION)" "$dist"
