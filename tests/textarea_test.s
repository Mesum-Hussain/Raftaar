# Wrapped rows, Unicode boundaries, vertical motion and caret scrolling in text areas.
.include "raftaar.inc"
.bss
.p2align 3
field: .zero TF_SIZE
pixels: .quad 0
width: .long 0
.text

.macro CHECK_ROW row, start, end
    mov edi, \row
    call ta_row_bounds
    cmp rax, \start
    jne .Lfail
    cmp rdx, \end
    jne .Lfail
.endm

.macro KEY key, pos, mods=0
    lea rdi, [rip + field]
    mov esi, \key
    xor edx, edx
    mov ecx, \mods
    call ta_key
    cmp eax, 1
    jne .Lfail
    cmp qword ptr [rip + field + TF_cur], \pos
    jne .Lfail
.endm

draw:
    PROLOGUE
    call ta_line_h
    imul r8d, eax, 3
    add r8d, [rip + g_mt + 4*MI_12]
    lea rdi, [rip + field]
    xor esi, esi
    xor edx, edx
    mov ecx, [rip + width]
    mov r9d, 1
    push 0
    push 0
    call ui_textarea
    add rsp, 16
    EPILOGUE

FN main
    PROLOGUE
    call app_load_fonts
    call ui_update_metrics
    lea rdi, [rip + g_face_ui]
    lea rsi, [rip + text]
    mov edx, 10                # "alpha beta" fits; wrap after "alpha "
    call text_width
    inc eax                    # allow subpixel rounding in glyph advances
    add eax, [rip + g_mt + 4*MI_24]
    mov [rip + width], eax
    lea rdi, [rip + field]
    lea rsi, [rip + text]
    mov edx, text_end - text
    call tf_set
    lea rdi, [rip + field]
    mov esi, [rip + width]
    call ta_layout
    cmp eax, 5
    jne .Lfail
    CHECK_ROW 0, 0, 6
    CHECK_ROW 1, 6, 16
    CHECK_ROW 2, 17, 17
    CHECK_ROW 3, 18, 19
    CHECK_ROW 4, 20, 20
    mov edi, 6
    call ta_row_of
    cmp eax, 1
    jne .Lfail
    lea rdi, [rip + field]
    xor esi, esi
    call ta_row_limit
    cmp rax, 5
    jne .Lfail

    mov qword ptr [rip + field + TF_cur], 4
    mov qword ptr [rip + field + TF_anchor], 4
    KEY KEY_DOWN, 10
    KEY KEY_DOWN, 17
    KEY KEY_DOWN, 19
    KEY KEY_UP, 17
    KEY KEY_UP, 10
    KEY KEY_DOWN, 17, MOD_SHIFT
    cmp qword ptr [rip + field + TF_anchor], 10
    jne .Lfail
    KEY KEY_HOME, 17
    KEY KEY_UP, 6
    KEY KEY_HOME, 0
    KEY KEY_END, 16
    KEY KEY_HOME, 0, MOD_CTRL
    KEY KEY_END, 20, MOD_CTRL

    mov edi, 320 * 240 * 4
    call mem_alloc
    mov [rip + pixels], rax
    mov rdi, rax
    mov esi, 320
    mov edx, 240
    mov ecx, 320
    call gfx_set_target
    call draw
    cmp dword ptr [rip + field + TF_top], 2
    jne .Lfail
    cmp dword ptr [rip + field + TF_scroll], 0
    jne .Lfail
    KEY KEY_HOME, 0, MOD_CTRL
    call draw
    cmp dword ptr [rip + field + TF_top], 0
    jne .Lfail
    # Mouse placement and dragging use visual rows as well.
    mov eax, [rip + g_mt + 4*MI_10]
    inc eax
    mov [rip + g_mx], eax
    call ta_line_h
    add eax, [rip + g_mt + 4*MI_6]
    inc eax
    mov [rip + g_my], eax
    mov dword ptr [rip + g_pressed], 1 << BTN_LEFT
    call draw
    cmp qword ptr [rip + field + TF_cur], 6
    jne .Lfail
    cmp qword ptr [rip + field + TF_anchor], 6
    jne .Lfail
    mov dword ptr [rip + g_pressed], 0
    mov dword ptr [rip + g_mdown], 1 << BTN_LEFT
    call ta_line_h
    add [rip + g_my], eax
    call draw
    cmp qword ptr [rip + field + TF_cur], 17
    jne .Lfail
    cmp qword ptr [rip + field + TF_anchor], 6
    jne .Lfail
    mov dword ptr [rip + g_mdown], 0
    mov dword ptr [rip + g_active], 0
    mov dword ptr [rip + g_mx], -10000
    mov dword ptr [rip + g_my], -10000
    # A resize reflows the text without changing its bytes or cursor.
    mov dword ptr [rip + width], 300
    call draw
    lea rdi, [rip + field]
    call ta_lines
    cmp eax, 4
    jne .Lfail
    lea rdi, [rip + field]
    call tf_text
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + text]
    mov ecx, text_end - text
    call str_eq
    test eax, eax
    jz .Lfail

    lea rdi, [rip + field]
    lea rsi, [rip + unicode]
    mov edx, unicode_end - unicode
    call tf_set
    lea rdi, [rip + field]
    mov esi, [rip + g_mt + 4*MI_24]
    inc esi                    # narrower than any glyph
    call ta_layout
    cmp eax, 3
    jne .Lfail
    CHECK_ROW 0, 0, 2
    CHECK_ROW 1, 2, 5
    CHECK_ROW 2, 5, 9
    lea rdi, [rip + field]
    mov esi, 1
    call ta_row_limit
    cmp rax, 2
    jne .Lfail
    KEY KEY_HOME, 0, MOD_CTRL
    KEY KEY_DOWN, 2
    KEY KEY_DOWN, 5
    KEY KEY_DOWN, 9
    KEY KEY_UP, 2
    KEY KEY_UP, 0

    lea rdi, [rip + field]
    call tf_clear
    lea rdi, [rip + field]
    call ta_lines
    cmp eax, 1
    jne .Lfail
    CHECK_ROW 0, 0, 0
    mov rdi, [rip + pixels]
    call mem_free
    lea rdi, [rip + field + TF_sb]
    call sb_free
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lfail:
    mov eax, 1
    EPILOGUE
.section .rodata
text: .ascii "alpha beta gamma\n\nz\n"
text_end:
unicode: .ascii "\303\251\344\270\255\360\237\230\200"
unicode_end:
ok: .asciz "ok\n"
