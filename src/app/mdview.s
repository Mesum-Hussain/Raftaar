# markdown preview: a Markdown file drawn as a page in place of its text (DF_PREVIEW), from the
# buffer as it is, unsaved edits included. A switch in the pane's corner goes between the two.
.include "raftaar.inc"

.equ ID_MD_PREVIEW, 0x4d01
.equ ID_MD_EDIT, 0x4d02
.equ ID_MD_SCROLL, 0x4d03

# styles of a run of text
.equ ST_BOLD, 1
.equ ST_ITALIC, 2
.equ ST_CODE, 4
.equ ST_STRIKE, 8
.equ ST_LINK, 16
# fl_opt
.equ FO_QUOTE, 1                # the lines after the first start with the quote's mark

# blocks: pg_kind, md_prev
.equ BK_PARA, 1
.equ BK_LIST, 2
.equ BK_QUOTE, 3
.equ BK_HEAD, 4
.equ BK_RULE, 5
.equ BK_CODE, 6
.equ BK_TABLE, 7

.equ TB_MAXC, 16                # columns of a table
.equ WBUF, 1024
.equ HOT_MAX, 1000              # longest link followed

.bss
.p2align 3
md_face_it: .zero FACE_SIZE     # the text's face, slanted
md_face_h1: .zero FACE_SIZE
md_face_h2: .zero FACE_SIZE
md_face_h3: .zero FACE_SIZE
md_doc: .quad 0
md_end: .quad 0                 # end of the text
md_sb: .zero SB_SIZE
md_hotlen: .quad 0
pg_start: .quad 0               # the paragraph being gathered
pg_end: .quad 0
pg_mark: .quad 0                # a list item's number
fl_face: .quad 0                # flow: what the caller sets
fl_url: .quad 0
fl_urllen: .quad 0
fl_wurl: .quad 0                # the link of the word in the buffer
fl_wurllen: .quad 0
fl_linkend: .quad 0             # where the link's text ends, and where the text goes on
fl_linkafter: .quad 0
fl_codeend: .quad 0             # the closing marks of the code span
fl_lasturl: .quad 0
lp_close: .quad 0               # link_parse's answer
lp_url: .quad 0
lp_urllen: .quad 0
lp_after: .quad 0
tb_cell: .zero TB_MAXC * 16     # a row's cells: ptr, len
md_px: .long 0                  # the size the faces were made for
md_lh: .long 0                  # line height of the text
md_view_h: .long 0
md_cx0: .long 0                 # the column: left edge and width
md_cw: .long 0
md_y: .long 0                   # where the next line goes
md_cy0: .long 0                 # the part of the page on screen
md_cy1: .long 0
md_nodraw: .long 0              # measuring
md_hot: .long 0                 # a link is under the pointer (md_hotbuf)
md_prev: .long 0                # the block before
md_fence: .long 0               # inside a code block: the mark that closes it
md_fence_n: .long 0
md_fence_ind: .long 0
md_codebg: .long 0
md_list_x: .long 0              # where the last list item's text began, from the column's edge
md_tg: .long 0                  # this pane has the switch
md_over: .long 0                # the pointer is over it
md_pressed: .long 0
pg_kind: .long 0
pg_level: .long 0
pg_marklen: .long 0             # 0: a bullet
pg_task: .long 0                # 1 open, 2 done
pg_ind: .long 0
fl_color: .long 0
fl_lh: .long 0
fl_base: .long 0                # styles of the whole block
fl_opt: .long 0
fl_x0: .long 0
fl_x1: .long 0
fl_x: .long 0
fl_maxx: .long 0
fl_st: .long 0
fl_wst: .long 0
fl_tst: .long 0                 # the styles of the piece being drawn
fl_wlen: .long 0
fl_space: .long 0               # a blank came before the word
fl_any: .long 0                 # the line has something on it
fl_codeticks: .long 0
fl_lead: .long 0                # the blank before the piece is part of it (a link's words)
fl_lastst: .long 0              # the link and strike styles of the piece before, on this line
tg_x: .long 0
tg_y: .long 0
tg_w1: .long 0
tg_w2: .long 0
tg_h: .long 0
tb_n: .long 0
tb_tw: .long 0
tb_y0: .long 0
tb_w: .zero TB_MAXC * 4
tb_al: .zero TB_MAXC * 4        # 1 right, 2 centered
fl_wbuf: .zero WBUF
md_hotbuf: .zero 1024

.text

# md_is(doc) -> 1 for a Markdown file that can be shown as a page
FN md_is
    xor eax, eax
    test rdi, rdi
    jz 1f
    cmp qword ptr [rdi + DOC_diff], 0
    jne 1f
    test dword ptr [rdi + DOC_flags], DF_READONLY
    jnz 1f
    mov rdi, [rdi + DOC_lang]
    test rdi, rdi
    jz 1f
    mov rdi, [rdi + GR_name]
    test rdi, rdi
    jz 1f
    push rdi
    call strlen
    pop rdi
    mov rsi, rax
    lea rdx, [rip + .Ls_markdown]
    call str_eq_cstr
1:  ret

# md_active() -> 1 while the document with the keys is shown as a page
FN md_active
    xor eax, eax
    mov rcx, [rip + g_doc]
    test rcx, rcx
    jz 1f
    test dword ptr [rcx + DOC_flags], DF_PREVIEW
    setnz al
1:  ret

FN cmd_toggle_md_preview
    push rbx
    mov rbx, [rip + g_doc]
    mov rdi, rbx
    call md_is
    test eax, eax
    jz 1f
    xor dword ptr [rbx + DOC_flags], DF_PREVIEW
    mov dword ptr [rip + g_dirty], 1
1:  pop rbx
    ret

# md_describe(doc, sb): " preview=1" for a page (print-state)
FN md_describe
    test dword ptr [rdi + DOC_flags], DF_PREVIEW
    jz 1f
    mov rdi, rsi
    lea rsi, [rip + .Ls_state]
    jmp sb_push_cstr
1:  ret

# md_key(keysym, cp, mods) -> 1 when used: the page scrolls
FN md_key
    push rbx
    mov rbx, [rip + g_doc]
    xor eax, eax
    test rbx, rbx
    jz .Lmk_ret
    mov eax, [rip + md_lh]
    lea ecx, [rax + rax*2]      # three lines
    mov edx, [rip + md_view_h]
    sub edx, eax                # a page less a line
    cmp edi, KEY_DOWN
    je .Lmk_add
    cmp esi, 'j'
    je .Lmk_add
    cmp edi, KEY_UP
    je .Lmk_sub
    cmp esi, 'k'
    je .Lmk_sub
    mov ecx, edx
    cmp edi, KEY_PAGEDOWN
    je .Lmk_add
    cmp esi, ' '
    je .Lmk_add
    cmp edi, KEY_PAGEUP
    je .Lmk_sub
    cmp edi, KEY_HOME
    jne 1f
    mov dword ptr [rbx + DOC_mdscroll], 0
    jmp .Lmk_used
1:  xor eax, eax
    cmp edi, KEY_END
    jne .Lmk_ret
    mov eax, [rbx + DOC_mdh]
    mov [rbx + DOC_mdscroll], eax
    jmp .Lmk_used
.Lmk_sub:
    neg ecx
.Lmk_add:
    add [rbx + DOC_mdscroll], ecx
.Lmk_used:
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
.Lmk_ret:
    pop rbx
    ret

# md_view(doc, x, y, w, h, keys) -> 1 when the page was drawn in place of the editor. For a Markdown
#   file the switch takes its presses first; md_view_end draws it over the editor
FN md_view
    PROLOGUE 32
    mov rbx, rdi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov [rsp + 16], r9d
    mov dword ptr [rip + md_tg], 0
    mov dword ptr [rip + md_over], 0
    call md_is
    test eax, eax
    jz .Lmv_no
    # the find bar is the editor's, and in the same corner
    cmp dword ptr [rsp + 16], 0
    je 1f
    call find_is_open
    test eax, eax
    jz 1f
    and dword ptr [rbx + DOC_flags], ~DF_PREVIEW
    jmp .Lmv_no
1:  mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call tg_rect
    mov [rip + md_tg], eax
    test eax, eax
    jz 2f
    mov rdi, rbx
    call tg_input
    mov [rip + md_over], eax
    # a press on the switch is not one on what is under it
    test eax, eax
    jz 2f
    mov eax, [rip + g_pressed]
    mov [rip + md_pressed], eax
    mov dword ptr [rip + g_pressed], 0
2:  test dword ptr [rbx + DOC_flags], DF_PREVIEW
    jz .Lmv_no
    mov rdi, rbx
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    call md_draw
    mov rdi, rbx
    call md_view_end
    mov eax, 1
    EPILOGUE
.Lmv_no:
    xor eax, eax
    EPILOGUE

# md_view_end(doc): the switch, over what the pane shows
FN md_view_end
    push rbx
    mov rbx, rdi
    cmp dword ptr [rip + md_tg], 0
    je 2f
    cmp dword ptr [rip + md_over], 0
    je 1f
    mov eax, [rip + md_pressed]
    mov [rip + g_pressed], eax
1:  mov rdi, rbx
    call tg_draw
    mov dword ptr [rip + md_tg], 0
2:  pop rbx
    ret

# tg_rect(x, y, w, h) -> 1 when the pane has room for the switch: its place in tg_*
tg_rect:
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    lea rdi, [rip + g_face_small]
    lea rsi, [rip + .Ls_preview]
    mov edx, 7
    call text_width
    M ecx, MI_10
    lea eax, [rax + rcx*2]
    mov [rip + tg_w1], eax
    lea rdi, [rip + g_face_small]
    lea rsi, [rip + .Ls_edit]
    mov edx, 4
    call text_width
    M ecx, MI_10
    lea eax, [rax + rcx*2]
    mov [rip + tg_w2], eax
    M eax, MI_24
    mov [rip + tg_h], eax
    mov ebx, [rip + tg_w1]
    add ebx, [rip + tg_w2]
    M ecx, MI_2
    lea ebx, [rbx + rcx*2]      # the box
    M ecx, MI_24
    lea edx, [rbx + rcx*2]
    xor eax, eax
    cmp edx, r14d
    jg 1f
    lea eax, [r12 + r14]
    sub eax, ecx                # clear of the scrollbar
    sub eax, ebx
    mov [rip + tg_x], eax
    M ecx, MI_8
    lea eax, [r13 + rcx]
    mov [rip + tg_y], eax
    mov eax, 1
1:  EPILOGUE

# tg_input(doc) -> 1 while the pointer is over the switch; a press turns it
tg_input:
    PROLOGUE
    mov rbx, rdi
    M r12d, MI_2
    mov edi, ID_MD_PREVIEW
    mov esi, [rip + tg_x]
    add esi, r12d
    mov edx, [rip + tg_y]
    add edx, r12d
    mov ecx, [rip + tg_w1]
    mov r8d, [rip + tg_h]
    call ui_btn
    test eax, UB_PRESS
    jz 1f
    or dword ptr [rbx + DOC_flags], DF_PREVIEW
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov dword ptr [rip + g_dirty], 1
1:  mov edi, ID_MD_EDIT
    mov esi, [rip + tg_x]
    add esi, r12d
    add esi, [rip + tg_w1]
    mov edx, [rip + tg_y]
    add edx, r12d
    mov ecx, [rip + tg_w2]
    mov r8d, [rip + tg_h]
    call ui_btn
    test eax, UB_PRESS
    jz 2f
    and dword ptr [rbx + DOC_flags], ~DF_PREVIEW
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov dword ptr [rip + g_dirty], 1
2:  mov edi, [rip + tg_x]
    mov esi, [rip + tg_y]
    mov edx, [rip + tg_w1]
    add edx, [rip + tg_w2]
    lea edx, [rdx + r12*2]
    mov ecx, [rip + tg_h]
    lea ecx, [rcx + r12*2]
    call ui_in
    EPILOGUE

# tg_draw(doc): Preview | Edit, the mode it is in marked
tg_draw:
    PROLOGUE 16
    mov rbx, rdi
    M r12d, MI_2
    mov r13d, [rip + tg_w1]
    add r13d, [rip + tg_w2]
    lea r13d, [r13 + r12*2]
    mov r14d, [rip + tg_h]
    lea r14d, [r14 + r12*2]
    mov edi, [rip + tg_x]
    mov esi, [rip + tg_y]
    mov edx, r13d
    mov ecx, r14d
    M r8d, MI_RADIUS
    COLOR r9d, T_BORDER
    COLOR eax, T_POPUP
    push rax
    push rax
    call gfx_frame
    add rsp, 16
    # the mode it is in
    mov edi, [rip + tg_x]
    add edi, r12d
    mov edx, [rip + tg_w1]
    COLOR r15d, T_FG            # Preview's label
    COLOR eax, T_MUTED
    mov [rsp], eax              # Edit's
    test dword ptr [rbx + DOC_flags], DF_PREVIEW
    jnz 1f
    add edi, edx
    mov edx, [rip + tg_w2]
    mov [rsp], r15d
    mov r15d, eax
1:  mov esi, [rip + tg_y]
    add esi, r12d
    mov ecx, [rip + tg_h]
    M r8d, MI_4
    COLOR r9d, T_ACTIVE
    call gfx_round_rect
    lea rdi, [rip + g_face_small]
    mov esi, [rip + tg_x]
    add esi, r12d
    mov edx, [rip + tg_y]
    add edx, r12d
    mov ecx, [rip + tg_w1]
    mov r8d, [rip + tg_h]
    lea r9, [rip + .Ls_preview]
    push r15
    push r15
    call ui_text_center
    add rsp, 16
    lea rdi, [rip + g_face_small]
    mov esi, [rip + tg_x]
    add esi, r12d
    add esi, [rip + tg_w1]
    mov edx, [rip + tg_y]
    add edx, r12d
    mov ecx, [rip + tg_w2]
    mov r8d, [rip + tg_h]
    lea r9, [rip + .Ls_edit]
    mov eax, [rsp]
    push rax
    push rax
    call ui_text_center
    add rsp, 16
    mov edi, [rip + tg_x]
    mov esi, [rip + tg_y]
    mov edx, r13d
    mov ecx, r14d
    call ui_in
    test eax, eax
    jz 2f
    mov dword ptr [rip + g_cursor], CUR_POINTER
2:  EPILOGUE

# md_faces(): the slanted face and the headings', for the size of the editor's text
md_faces:
    push rbx
    mov ebx, [rip + g_face_code + FACE_px]
    cmp ebx, [rip + md_px]
    je 1f
    mov [rip + md_px], ebx
    lea rdi, [rip + md_face_it]
    mov rsi, [rip + g_font_code]
    mov edx, ebx
    call face_init
    mov dword ptr [rip + md_face_it + FACE_slant], 1
    lea rdi, [rip + md_face_h1]
    mov rsi, [rip + g_font_code]
    lea edx, [rbx + rbx]
    call face_init
    lea rdi, [rip + md_face_h2]
    mov rsi, [rip + g_font_code]
    lea edx, [rbx + rbx*2]
    shr edx, 1
    call face_init
    lea rdi, [rip + md_face_h3]
    mov rsi, [rip + g_font_code]
    lea edx, [rbx + rbx*4]
    shr edx, 2
    call face_init
1:  # prose has more room between its lines than code
    mov eax, ebx
    shr eax, 2
    add eax, [rip + g_lh]
    mov [rip + md_lh], eax
    pop rbx
    ret

# md_clamp(doc, view height): the scroll inside the page as last laid out
md_clamp:
    mov eax, [rdi + DOC_mdh]
    sub eax, esi
    jns 1f
    xor eax, eax
1:  cmp [rdi + DOC_mdscroll], eax
    jle 2f
    mov [rdi + DOC_mdscroll], eax
2:  cmp dword ptr [rdi + DOC_mdscroll], 0
    jge 3f
    mov dword ptr [rdi + DOC_mdscroll], 0
3:  ret

# md_draw(doc, x, y, w, h)
FN md_draw
    PROLOGUE 48
    mov rbx, rdi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov edi, esi
    mov esi, edx
    mov edx, ecx
    mov ecx, r8d
    COLOR r8d, T_BG
    call gfx_fill
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call gfx_clip_push
    call md_faces
    mov eax, [rsp + 12]
    mov [rip + md_view_h], eax
    # the wheel; a press gives the pane the keys
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call ui_in
    test eax, eax
    jz 1f
    mov eax, [rip + g_scroll_y]
    add [rbx + DOC_mdscroll], eax
    test dword ptr [rip + g_pressed], 1 << BTN_LEFT
    jz 1f
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
1:  mov rdi, rbx
    mov esi, [rsp + 12]
    call md_clamp
    # the column
    mov edi, 32
    call sc
    mov r12d, eax
    mov r13d, [rsp + 8]
    sub r13d, r12d
    sub r13d, r12d
    mov edi, 900
    call sc
    cmp r13d, eax
    cmovg r13d, eax
    mov edi, 80
    call sc
    cmp r13d, eax
    cmovl r13d, eax
    mov eax, [rsp]
    add eax, r12d
    mov [rip + md_cx0], eax
    mov [rip + md_cw], r13d
    mov edi, 24
    call sc
    mov r14d, eax               # room above and below the page
    mov eax, [rsp + 4]
    mov [rip + md_cy0], eax
    add eax, [rsp + 12]
    mov [rip + md_cy1], eax
    mov eax, [rsp + 4]
    add eax, r14d
    sub eax, [rbx + DOC_mdscroll]
    mov [rip + md_y], eax
    mov dword ptr [rip + md_hot], 0
    mov dword ptr [rip + md_nodraw], 0
    mov dword ptr [rip + md_prev], 0
    mov dword ptr [rip + md_fence], 0
    mov dword ptr [rip + pg_kind], 0
    mov [rip + md_doc], rbx
    COLOR edi, T_BG
    COLOR esi, T_FG
    mov edx, 20
    call color_mix
    mov [rip + md_codebg], eax
    mov rdi, rbx
    call doc_len
    mov r15, rax
    mov rdi, rbx
    call doc_contiguous
    mov rdi, rax
    mov rsi, r15
    call md_blocks
    # the page's height
    mov eax, [rip + md_y]
    add eax, [rbx + DOC_mdscroll]
    sub eax, [rsp + 4]
    add eax, r14d
    mov [rbx + DOC_mdh], eax
    # scrolled past its end (the text got shorter): another frame
    mov r15d, [rbx + DOC_mdscroll]
    mov rdi, rbx
    mov esi, [rsp + 12]
    call md_clamp
    cmp r15d, [rbx + DOC_mdscroll]
    je 2f
    mov dword ptr [rip + g_dirty], 1
2:  # a link under the pointer
    cmp dword ptr [rip + md_hot], 0
    je 3f
    mov dword ptr [rip + g_cursor], CUR_POINTER
    test dword ptr [rip + g_pressed], 1 << BTN_LEFT
    jz 3f
    call md_open_link
3:  call gfx_clip_pop
    mov eax, [rbx + DOC_mdh]
    mov ecx, [rsp + 12]
    push rcx
    push rax
    mov edi, ID_MD_SCROLL
    mov esi, [rsp + 16]
    add esi, [rsp + 16 + 8]
    M eax, MI_12
    sub esi, eax
    mov edx, [rsp + 16 + 4]
    mov ecx, eax
    mov r8d, [rsp + 16 + 12]
    lea r9, [rbx + DOC_mdscroll]
    call ui_scrollbar
    add rsp, 16
    EPILOGUE

# md_open_link(): the link in md_hotbuf: a URL in the browser, a file beside this one in a tab
md_open_link:
    PROLOGUE
    lea r12, [rip + md_hotbuf]
    mov r13, [rip + md_hotlen]
    cmp byte ptr [r12], '#'
    je .Lol_ret
    mov rdi, r12
    lea rsi, [r12 + r13]
    call is_url
    test eax, eax
    jz .Lol_file
    mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov rbx, rax
    mov rdi, rax
    call desktop_open
    mov rdi, rbx
    call mem_free
    jmp .Lol_ret
.Lol_file:
    # what follows # is a place in the file
    xor ecx, ecx
1:  cmp rcx, r13
    jae 2f
    cmp byte ptr [r12 + rcx], '#'
    je 2f
    inc rcx
    jmp 1b
2:  mov r13, rcx
    test r13, r13
    jz .Lol_ret
    lea rdi, [rip + md_sb]
    call sb_clear
    cmp byte ptr [r12], '/'
    je 4f
    mov rbx, [rip + md_doc]
    mov rbx, [rbx + DOC_path]
    test rbx, rbx
    jz .Lol_ret
    mov rdi, rbx
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call path_dirlen
    lea rdi, [rip + md_sb]
    mov rsi, rbx
    mov rdx, rax
    call sb_push
    lea rdi, [rip + md_sb]
    mov esi, '/'
    call sb_push_byte
3:  cmp r13, 2
    jb 4f
    cmp byte ptr [r12], '.'
    jne 4f
    cmp byte ptr [r12 + 1], '/'
    jne 4f
    add r12, 2
    sub r13, 2
    jmp 3b
4:  lea rdi, [rip + md_sb]
    mov rsi, r12
    mov rdx, r13
    call sb_push
    lea rdi, [rip + md_sb]
    xor esi, esi
    call sb_push_byte
    # only a file that is there: a tab for a missing one would be a new file
    mov rdi, [rip + md_sb + SB_ptr]
    xor esi, esi
    SYS SYS_access
    test eax, eax
    jnz .Lol_ret
    mov rdi, [rip + md_sb + SB_ptr]
    call app_open_file
.Lol_ret:
    EPILOGUE

# ---- blocks ----

# run_of(p, end, byte) -> how many of that byte start p
run_of:
    xor eax, eax
1:  cmp rdi, rsi
    jae 2f
    cmp byte ptr [rdi], dl
    jne 2f
    inc rdi
    inc eax
    jmp 1b
2:  ret

# has_byte(p, end, byte) -> 1 when the byte is there
has_byte:
    xor eax, eax
1:  cmp rdi, rsi
    jae 2f
    cmp byte ptr [rdi], dl
    je 3f
    inc rdi
    jmp 1b
3:  mov eax, 1
2:  ret

# is_blank(p, end) -> 1 for blanks alone
is_blank:
    mov eax, 1
1:  cmp rdi, rsi
    jae 2f
    movzx ecx, byte ptr [rdi]
    inc rdi
    cmp cl, ' '
    je 1b
    cmp cl, 9
    je 1b
    cmp cl, 13
    je 1b
    xor eax, eax
2:  ret

# line_end(p) -> rax the end of the line at p, rdx the start of the next one
line_end:
    mov rax, rdi
    mov rcx, [rip + md_end]
1:  cmp rax, rcx
    jae 2f
    cmp byte ptr [rax], 10
    je 3f
    inc rax
    jmp 1b
3:  lea rdx, [rax + 1]
    ret
2:  mov rdx, rax
    ret

# is_rule(p, end) -> 1 for a line of three or more -, * or _
is_rule:
    xor eax, eax
    movzx edx, byte ptr [rdi]
    cmp dl, '-'
    je 1f
    cmp dl, '*'
    je 1f
    cmp dl, '_'
    jne 4f
1:  xor ecx, ecx
2:  cmp rdi, rsi
    jae 3f
    movzx r8d, byte ptr [rdi]
    inc rdi
    cmp r8b, ' '
    je 2b
    cmp r8b, 9
    je 2b
    cmp r8b, dl
    jne 4f
    inc ecx
    jmp 2b
3:  cmp ecx, 3
    jb 4f
    mov eax, 1
4:  ret

# is_delim(p) -> 1 when the line at p is the row of dashes under a table's header
is_delim:
    push rbx
    xor ebx, ebx                # dashes
    mov rsi, [rip + md_end]
1:  cmp rdi, rsi
    jae 3f
    movzx eax, byte ptr [rdi]
    inc rdi
    cmp al, 10
    je 3f
    cmp al, '-'
    jne 2f
    inc ebx
    jmp 1b
2:  cmp al, '|'
    je 1b
    cmp al, ':'
    je 1b
    cmp al, ' '
    je 1b
    cmp al, 9
    je 1b
    cmp al, 13
    je 1b
    xor ebx, ebx
3:  xor eax, eax
    test ebx, ebx
    setnz al
    pop rbx
    ret

# list_marker(p, end) -> eax the length of a list item's mark with the blank after it (0: none),
#   edx 1 for a number
list_marker:
    xor eax, eax
    xor edx, edx
    lea rcx, [rdi + 1]
    cmp rcx, rsi
    jae 9f
    movzx r8d, byte ptr [rdi]
    cmp r8b, '-'
    je 1f
    cmp r8b, '*'
    je 1f
    cmp r8b, '+'
    jne 2f
1:  cmp byte ptr [rcx], ' '
    jne 9f
    mov eax, 2
    ret
2:  xor ecx, ecx                # digits
3:  lea r9, [rdi + rcx]
    cmp r9, rsi
    jae 9f
    movzx r8d, byte ptr [r9]
    cmp r8b, '0'
    jb 4f
    cmp r8b, '9'
    ja 4f
    inc ecx
    cmp ecx, 9
    jbe 3b
    ret
4:  test ecx, ecx
    jz 9f
    cmp r8b, '.'
    je 5f
    cmp r8b, ')'
    jne 9f
5:  lea r9, [rdi + rcx + 1]
    cmp r9, rsi
    jae 9f
    cmp byte ptr [r9], ' '
    jne 9f
    lea eax, [rcx + 2]
    mov edx, 1
9:  ret

# md_blocks(text, len): the page, a line of the text at a time
md_blocks:
    PROLOGUE 32
    mov r12, rdi
    lea r13, [rdi + rsi]
    mov [rip + md_end], r13
.Lb_line:
    cmp r12, r13
    jae .Lb_end
    mov rdi, r12
    call line_end
    mov r14, rax
    mov [rsp], rdx              # the next line
    cmp r14, r12
    jbe 1f
    cmp byte ptr [r14 - 1], 13
    jne 1f
    dec r14
1:  # its indentation
    mov rbx, r12
    xor r15d, r15d
2:  cmp rbx, r14
    jae 4f
    movzx eax, byte ptr [rbx]
    cmp al, ' '
    jne 3f
    inc r15d
    inc rbx
    jmp 2b
3:  cmp al, 9
    jne 4f
    add r15d, 4
    inc rbx
    jmp 2b
4:  cmp dword ptr [rip + md_fence], 0
    je .Lb_open
    # in a code block until its mark comes again
    mov rdi, rbx
    mov rsi, r14
    mov edx, [rip + md_fence]
    call run_of
    cmp eax, [rip + md_fence_n]
    jb .Lb_code
    lea rdi, [rbx + rax]
    mov rsi, r14
    call is_blank
    test eax, eax
    jz .Lb_code
    call code_end
    mov dword ptr [rip + md_fence], 0
    jmp .Lb_next
.Lb_code:
    # less the indentation its opening line had
    mov rdi, r12
    mov ecx, [rip + md_fence_ind]
5:  test ecx, ecx
    jz 6f
    cmp rdi, r14
    jae 6f
    cmp byte ptr [rdi], ' '
    jne 6f
    inc rdi
    dec ecx
    jmp 5b
6:  mov rsi, r14
    call code_line
    jmp .Lb_next
.Lb_open:
    cmp rbx, r14
    jb 7f
    call para_flush
    jmp .Lb_next
7:  movzx eax, byte ptr [rbx]
    cmp al, '`'
    je 8f
    cmp al, '~'
    jne .Lb_head
8:  mov rdi, rbx
    mov rsi, r14
    mov edx, eax
    call run_of
    cmp eax, 3
    jb .Lb_head
    mov [rip + md_fence_n], eax
    movzx eax, byte ptr [rbx]
    mov [rip + md_fence], eax
    mov [rip + md_fence_ind], r15d
    call para_flush
    call code_begin
    jmp .Lb_next
.Lb_head:
    cmp byte ptr [rbx], '#'
    jne .Lb_rule
    mov rdi, rbx
    mov rsi, r14
    mov edx, '#'
    call run_of
    cmp eax, 6
    ja .Lb_rule
    lea rdi, [rbx + rax]
    cmp rdi, r14
    je 9f
    cmp byte ptr [rdi], ' '
    jne .Lb_rule
9:  mov [rsp + 8], eax
    mov [rsp + 16], rdi
    call para_flush
    mov edi, [rsp + 8]
    mov rsi, [rsp + 16]
    mov rdx, r14
    call heading
    jmp .Lb_next
.Lb_rule:
    mov rdi, rbx
    mov rsi, r14
    call is_rule
    test eax, eax
    jz .Lb_table
    call para_flush
    call rule
    jmp .Lb_next
.Lb_table:
    # a row with a row of dashes under it
    mov rdi, rbx
    mov rsi, r14
    mov edx, '|'
    call has_byte
    test eax, eax
    jz .Lb_quote
    mov rdi, [rsp]
    call is_delim
    test eax, eax
    jz .Lb_quote
    call para_flush
    mov rdi, r12
    call table
    mov [rsp], rax
    jmp .Lb_next
.Lb_quote:
    cmp byte ptr [rbx], '>'
    jne .Lb_list
    lea rdi, [rbx + 1]
    cmp dword ptr [rip + pg_kind], BK_QUOTE
    jne 1f
    mov [rip + pg_end], r14
    jmp .Lb_next
1:  mov [rsp + 8], rdi
    call para_flush
    mov rdi, [rsp + 8]
    mov dword ptr [rip + pg_kind], BK_QUOTE
    mov [rip + pg_start], rdi
    mov [rip + pg_end], r14
    jmp .Lb_next
.Lb_list:
    mov rdi, rbx
    mov rsi, r14
    call list_marker
    test eax, eax
    jz .Lb_text
    mov [rsp + 8], eax
    mov [rsp + 12], edx
    call para_flush
    mov eax, [rsp + 8]
    mov dword ptr [rip + pg_kind], BK_LIST
    mov ecx, r15d
    shr ecx, 1
    cmp ecx, 6
    jbe 1f
    mov ecx, 6
1:  mov [rip + pg_level], ecx
    mov [rip + pg_mark], rbx
    xor ecx, ecx
    cmp dword ptr [rsp + 12], 0
    je 2f
    lea ecx, [rax - 1]
2:  mov [rip + pg_marklen], ecx
    lea rdi, [rbx + rax]
3:  cmp rdi, r14
    jae 4f
    cmp byte ptr [rdi], ' '
    jne 4f
    inc rdi
    jmp 3b
4:  # a task: [ ] or [x]
    mov dword ptr [rip + pg_task], 0
    lea rax, [rdi + 3]
    cmp rax, r14
    ja 7f
    cmp byte ptr [rdi], '['
    jne 7f
    cmp byte ptr [rdi + 2], ']'
    jne 7f
    cmp rax, r14
    je 5f
    cmp byte ptr [rax], ' '
    jne 7f
5:  movzx ecx, byte ptr [rdi + 1]
    mov edx, 1
    cmp cl, ' '
    je 6f
    or cl, 0x20
    cmp cl, 'x'
    jne 7f
    mov edx, 2
6:  mov [rip + pg_task], edx
    mov rdi, rax
7:  mov [rip + pg_start], rdi
    mov [rip + pg_end], r14
    jmp .Lb_next
.Lb_text:
    # more of the paragraph, the item or the quote before it
    cmp dword ptr [rip + pg_kind], 0
    je 1f
    mov [rip + pg_end], r14
    jmp .Lb_next
1:  mov dword ptr [rip + pg_kind], BK_PARA
    mov [rip + pg_start], rbx
    mov [rip + pg_end], r14
    # indented under a list item: it belongs to it
    xor eax, eax
    cmp r15d, 2
    jb 2f
    cmp dword ptr [rip + md_prev], BK_LIST
    jne 2f
    mov eax, [rip + md_list_x]
2:  mov [rip + pg_ind], eax
.Lb_next:
    mov r12, [rsp]
    jmp .Lb_line
.Lb_end:
    call para_flush
    cmp dword ptr [rip + md_fence], 0
    je 1f
    call code_end
1:  EPILOGUE

# block_gap(kind): the room above a block
block_gap:
    mov eax, [rip + md_prev]
    test eax, eax
    jz 3f
    mov ecx, [rip + md_lh]
    mov edx, ecx
    shr edx, 1
    cmp edi, BK_LIST
    jne 1f
    cmp eax, BK_LIST
    jne 1f
    mov edx, ecx                # the items of a list stay together
    shr edx, 3
1:  cmp edi, BK_HEAD
    jne 2f
    mov edx, ecx
2:  add [rip + md_y], edx
3:  ret

# flow_body(): flow's settings for plain text across the column
flow_body:
    lea rax, [rip + g_face_code]
    mov [rip + fl_face], rax
    COLOR eax, T_FG
    mov [rip + fl_color], eax
    mov eax, [rip + md_lh]
    mov [rip + fl_lh], eax
    mov dword ptr [rip + fl_base], 0
    mov dword ptr [rip + fl_opt], 0
    mov eax, [rip + md_cx0]
    mov [rip + fl_x0], eax
    add eax, [rip + md_cw]
    mov [rip + fl_x1], eax
    ret

# para_flush(): draw the paragraph, list item or quote gathered so far
para_flush:
    PROLOGUE 16
    mov eax, [rip + pg_kind]
    test eax, eax
    jz .Lpf_ret
    cmp eax, BK_LIST
    je .Lpf_list
    cmp eax, BK_QUOTE
    je .Lpf_quote
    mov edi, BK_PARA
    call block_gap
    call flow_body
    mov eax, [rip + pg_ind]
    add [rip + fl_x0], eax
    jmp .Lpf_flow
.Lpf_list:
    mov edi, BK_LIST
    call block_gap
    call flow_body
    # three cells in for each level; then the mark and the text
    mov ebx, [rip + g_cw]
    lea r12d, [rbx + rbx*2]
    imul r12d, [rip + pg_level]
    add r12d, [rip + md_cx0]
    lea r13d, [rbx + rbx]
    mov eax, [rip + pg_marklen]
    test eax, eax
    jz 1f
    inc eax
    imul eax, ebx
    mov r13d, eax
1:  mov r14d, [rip + g_face_code + FACE_ascent]     # a task's box
    cmp dword ptr [rip + pg_task], 0
    je 2f
    lea r13d, [r14 + rbx]
2:  lea eax, [r12 + r13]
    mov [rip + fl_x0], eax
    sub eax, [rip + md_cx0]
    mov [rip + md_list_x], eax
    mov eax, [rip + md_y]
    cmp eax, [rip + md_cy1]
    jge .Lpf_flow
    add eax, [rip + md_lh]
    cmp eax, [rip + md_cy0]
    jle .Lpf_flow
    cmp dword ptr [rip + pg_task], 0
    je .Lpf_mark
    mov esi, [rip + md_lh]
    sub esi, r14d
    sar esi, 1
    add esi, [rip + md_y]
    mov edi, r12d
    mov edx, r14d
    mov ecx, r14d
    M r8d, MI_3
    cmp dword ptr [rip + pg_task], 2
    je 3f
    COLOR r9d, T_MUTED
    COLOR eax, T_BG
    push rax
    push rax
    call gfx_frame
    add rsp, 16
    jmp .Lpf_flow
3:  COLOR r9d, T_ACCENT         # done: the box filled
    call gfx_round_rect
    jmp .Lpf_flow
.Lpf_mark:
    cmp dword ptr [rip + pg_marklen], 0
    jne 4f
    # a bullet
    lea edx, [rbx + rbx*4]
    shr edx, 3
    cmp edx, 4
    jge 31f
    mov edx, 4
31: mov ecx, edx
    mov esi, [rip + md_lh]
    sub esi, edx
    sar esi, 1
    add esi, [rip + md_y]
    mov edi, ebx
    shr edi, 2
    add edi, r12d
    mov r8d, edx
    shr r8d, 1
    COLOR r9d, T_MUTED
    call gfx_round_rect
    jmp .Lpf_flow
4:  lea rdi, [rip + g_face_code]
    mov esi, r12d
    mov edx, [rip + md_lh]
    sub edx, [rip + g_face_code + FACE_ascent]
    sub edx, [rip + g_face_code + FACE_descent]
    sar edx, 1
    add edx, [rip + md_y]
    add edx, [rip + g_face_code + FACE_ascent]
    mov rcx, [rip + pg_mark]
    mov r8d, [rip + pg_marklen]
    COLOR r9d, T_MUTED
    call text_draw
    jmp .Lpf_flow
.Lpf_quote:
    mov edi, BK_QUOTE
    call block_gap
    call flow_body
    mov edi, 16
    call sc
    add [rip + fl_x0], eax
    COLOR eax, T_MUTED
    mov [rip + fl_color], eax
    mov dword ptr [rip + fl_opt], FO_QUOTE
    mov eax, [rip + md_y]
    mov [rsp], eax
    mov rdi, [rip + pg_start]
    mov rsi, [rip + pg_end]
    sub rsi, rdi
    call flow
    # the bar along it
    mov edi, 3
    call sc
    mov edx, eax
    mov edi, [rip + md_cx0]
    mov esi, [rsp]
    mov ecx, [rip + md_y]
    sub ecx, esi
    COLOR r8d, T_BORDER
    call gfx_fill
    jmp .Lpf_done
.Lpf_flow:
    mov rdi, [rip + pg_start]
    mov rsi, [rip + pg_end]
    sub rsi, rdi
    call flow
.Lpf_done:
    mov eax, [rip + pg_kind]
    mov [rip + md_prev], eax
    mov dword ptr [rip + pg_kind], 0
.Lpf_ret:
    EPILOGUE

# heading(level, p, end)
heading:
    PROLOGUE
    mov ebx, edi
    mov r12, rsi
    mov r13, rdx
1:  cmp r12, r13
    jae 2f
    cmp byte ptr [r12], ' '
    jne 2f
    inc r12
    jmp 1b
2:  # blanks and closing marks at its end
    cmp r13, r12
    jbe 4f
    movzx eax, byte ptr [r13 - 1]
    cmp al, ' '
    je 3f
    cmp al, '#'
    jne 4f
3:  dec r13
    jmp 2b
4:  mov edi, BK_HEAD
    call block_gap
    call flow_body
    mov dword ptr [rip + fl_base], ST_BOLD
    lea rax, [rip + md_face_h1]
    cmp ebx, 1
    je 5f
    lea rax, [rip + md_face_h2]
    cmp ebx, 2
    je 5f
    lea rax, [rip + md_face_h3]
    cmp ebx, 3
    je 5f
    lea rax, [rip + g_face_code]
5:  mov [rip + fl_face], rax
    mov ecx, [rax + FACE_ascent]
    add ecx, [rax + FACE_descent]
    lea ecx, [rcx + rcx*4]
    shr ecx, 2
    cmp ecx, [rip + md_lh]
    jge 6f
    mov ecx, [rip + md_lh]
6:  mov [rip + fl_lh], ecx
    mov rdi, r12
    mov rsi, r13
    sub rsi, r12
    call flow
    # the two largest have a line under them
    cmp ebx, 2
    ja 7f
    M eax, MI_6
    add [rip + md_y], eax
    mov edi, [rip + md_cx0]
    mov esi, [rip + md_y]
    mov edx, [rip + md_cw]
    mov ecx, [rip + g_border]
    COLOR r8d, T_BORDER
    call gfx_fill
    mov eax, [rip + g_border]
    add [rip + md_y], eax
7:  mov dword ptr [rip + md_prev], BK_HEAD
    EPILOGUE

# rule(): a line across the column
rule:
    push rbx
    mov edi, BK_RULE
    call block_gap
    mov ebx, [rip + md_lh]
    shr ebx, 2
    add [rip + md_y], ebx
    mov edi, [rip + md_cx0]
    mov esi, [rip + md_y]
    mov edx, [rip + md_cw]
    M ecx, MI_2
    COLOR r8d, T_BORDER
    call gfx_fill
    M eax, MI_2
    add eax, ebx
    add [rip + md_y], eax
    mov dword ptr [rip + md_prev], BK_RULE
    pop rbx
    ret

# code_pad(): a band of a code block's background, above its first line and under its last
code_pad:
    push rbx
    M ebx, MI_8
    mov edi, [rip + md_cx0]
    mov esi, [rip + md_y]
    mov edx, [rip + md_cw]
    mov ecx, ebx
    mov r8d, [rip + md_codebg]
    call gfx_fill
    add [rip + md_y], ebx
    pop rbx
    ret

code_begin:
    push rbx
    mov edi, BK_CODE
    call block_gap
    call code_pad
    pop rbx
    ret

code_end:
    push rbx
    call code_pad
    mov dword ptr [rip + md_prev], BK_CODE
    pop rbx
    ret

# code_line(p, end): a line of a code block as it is; one wider than the column goes on below
code_line:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    sub r13, r12
    M eax, MI_12
    mov [rsp], eax
    mov r14d, [rip + md_cw]
    sub r14d, eax
    sub r14d, eax
    cmp r14d, [rip + g_cw]
    jge .Lcl_row
    mov r14d, [rip + g_cw]
.Lcl_row:
    mov rbx, r13
    mov ecx, [rip + g_cw]
    imul rcx, r13
    cmp rcx, r14
    jle 1f
    lea rdi, [rip + g_face_code]
    mov rsi, r12
    mov rdx, r13
    mov ecx, r14d
    call text_fit
    mov rbx, rax
    test rbx, rbx
    jnz 1f
    mov rdi, r12
    mov rsi, r13
    call utf8_decode
    mov ebx, edx
1:  mov eax, [rip + md_y]
    cmp eax, [rip + md_cy1]
    jge 2f
    add eax, [rip + g_lh]
    cmp eax, [rip + md_cy0]
    jle 2f
    mov edi, [rip + md_cx0]
    mov esi, [rip + md_y]
    mov edx, [rip + md_cw]
    mov ecx, [rip + g_lh]
    mov r8d, [rip + md_codebg]
    call gfx_fill
    lea rdi, [rip + g_face_code]
    mov esi, [rip + md_cx0]
    add esi, [rsp]
    mov edx, [rip + md_y]
    add edx, [rip + g_base]
    mov rcx, r12
    mov r8, rbx
    COLOR r9d, T_FG
    call text_draw
2:  mov eax, [rip + g_lh]
    add [rip + md_y], eax
    add r12, rbx
    sub r13, rbx
    test r13, r13
    jg .Lcl_row
    EPILOGUE

# ---- tables ----

# row_parse(p, end) -> the number of cells in the row, each trimmed, in tb_cell
row_parse:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
1:  cmp r12, r13
    jae 3f
    movzx eax, byte ptr [r12]
    cmp al, ' '
    je 2f
    cmp al, 9
    jne 3f
2:  inc r12
    jmp 1b
3:  cmp r13, r12
    jbe 5f
    movzx eax, byte ptr [r13 - 1]
    cmp al, ' '
    je 4f
    cmp al, 9
    je 4f
    cmp al, 13
    jne 5f
4:  dec r13
    jmp 3b
5:  # the bars at its ends are not cells
    cmp r12, r13
    jae 6f
    cmp byte ptr [r12], '|'
    jne 6f
    inc r12
6:  cmp r13, r12
    jbe 7f
    cmp byte ptr [r13 - 1], '|'
    jne 7f
    dec r13
7:  xor ebx, ebx
    lea r15, [rip + tb_cell]
.Lrp_cell:
    cmp ebx, TB_MAXC
    jae .Lrp_done
    mov r14, r12
1:  cmp r12, r13
    jae 3f
    movzx eax, byte ptr [r12]
    cmp al, '\\'
    jne 2f
    add r12, 2
    cmp r12, r13
    jbe 1b
    mov r12, r13
    jmp 3f
2:  cmp al, '|'
    je 3f
    inc r12
    jmp 1b
3:  mov rdi, r14
    mov rsi, r12
4:  cmp rdi, rsi
    jae 5f
    cmp byte ptr [rdi], ' '
    jne 5f
    inc rdi
    jmp 4b
5:  cmp rsi, rdi
    jbe 6f
    cmp byte ptr [rsi - 1], ' '
    jne 6f
    dec rsi
    jmp 5b
6:  mov eax, ebx
    shl eax, 4
    mov [r15 + rax], rdi
    sub rsi, rdi
    mov [r15 + rax + 8], rsi
    inc ebx
    cmp r12, r13
    jae .Lrp_done
    inc r12
    jmp .Lrp_cell
.Lrp_done:
    mov eax, ebx
    EPILOGUE

# tb_cell_flow(cell, styles, x0, x1, nodraw) -> eax how wide its text ran, edx how tall; md_y stays
tb_cell_flow:
    PROLOGUE 16
    mov ebx, edi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov r12d, [rip + md_nodraw]
    mov r13d, [rip + md_y]
    mov [rip + md_nodraw], r8d
    call flow_body
    mov eax, [rsp]
    mov [rip + fl_base], eax
    mov eax, [rsp + 4]
    mov [rip + fl_x0], eax
    mov eax, [rsp + 8]
    mov [rip + fl_x1], eax
    mov eax, ebx
    shl eax, 4
    lea rcx, [rip + tb_cell]
    mov rdi, [rcx + rax]
    mov rsi, [rcx + rax + 8]
    call flow
    mov [rip + md_nodraw], r12d
    mov edx, [rip + md_y]
    sub edx, r13d
    mov [rip + md_y], r13d
    EPILOGUE

# tb_measure_row(p, end, styles): widen tb_w to the row's cells, each on one line
tb_measure_row:
    PROLOGUE 16
    mov [rsp], edx
    call row_parse
    mov r12d, eax
    xor ebx, ebx
1:  cmp ebx, r12d
    jae 3f
    cmp ebx, [rip + tb_n]
    jae 3f
    mov edi, ebx
    mov esi, [rsp]
    xor edx, edx
    mov ecx, 0x3fffff
    mov r8d, 1
    call tb_cell_flow
    lea rcx, [rip + tb_w]
    cmp eax, [rcx + rbx*4]
    jle 2f
    mov [rcx + rbx*4], eax
2:  inc ebx
    jmp 1b
3:  EPILOGUE

# tb_row(p, end, styles): a row, as tall as its tallest cell, and the line under it
tb_row:
    PROLOGUE 48
    mov [rsp], edx
    call row_parse
    mov r12d, eax
    M r13d, MI_12               # room beside a cell's text
    M r14d, MI_6                # and above and under it
    mov r15d, [rip + md_lh]
    xor ebx, ebx
1:  cmp ebx, r12d
    jae 3f
    cmp ebx, [rip + tb_n]
    jae 3f
    mov edi, ebx
    mov esi, [rsp]
    xor edx, edx
    lea rcx, [rip + tb_w]
    mov ecx, [rcx + rbx*4]
    sub ecx, r13d
    sub ecx, r13d
    mov r8d, 1
    call tb_cell_flow
    cmp edx, r15d
    jle 2f
    mov r15d, edx
2:  inc ebx
    jmp 1b
3:  lea r15d, [r15 + r14*2]
    mov [rsp + 4], r15d         # the row's height
    cmp dword ptr [rsp], 0
    je 4f
    mov edi, [rip + md_cx0]
    mov esi, [rip + md_y]
    mov edx, [rip + tb_tw]
    mov ecx, r15d
    mov r8d, [rip + md_codebg]
    call gfx_fill
4:  mov eax, [rip + md_y]
    mov [rsp + 8], eax
    add eax, r14d
    mov [rip + md_y], eax
    xor ebx, ebx
    mov r15d, [rip + md_cx0]    # the cell's left edge
.Ltr_cell:
    cmp ebx, r12d
    jae .Ltr_end
    cmp ebx, [rip + tb_n]
    jae .Ltr_end
    lea rcx, [rip + tb_w]
    mov eax, [rcx + rbx*4]
    mov [rsp + 12], eax
    sub eax, r13d
    sub eax, r13d
    mov [rsp + 16], eax         # room for its text
    mov dword ptr [rsp + 20], 0
    lea rcx, [rip + tb_al]
    cmp dword ptr [rcx + rbx*4], 0
    je 6f
    # right or centered: by the room a cell on one line leaves
    mov edi, ebx
    mov esi, [rsp]
    xor edx, edx
    mov ecx, 0x3fffff
    mov r8d, 1
    call tb_cell_flow
    mov ecx, [rsp + 16]
    sub ecx, eax
    jle 6f
    lea rdx, [rip + tb_al]
    cmp dword ptr [rdx + rbx*4], 2
    jne 5f
    shr ecx, 1
5:  mov [rsp + 20], ecx
6:  mov edi, ebx
    mov esi, [rsp]
    mov edx, r15d
    add edx, r13d
    mov ecx, edx
    add ecx, [rsp + 16]
    add edx, [rsp + 20]
    cmp dword ptr [rsp + 20], 0
    je 7f
    add ecx, r13d               # moved text keeps to its one line
7:  xor r8d, r8d
    call tb_cell_flow
    add r15d, [rsp + 12]
    inc ebx
    jmp .Ltr_cell
.Ltr_end:
    mov eax, [rsp + 8]
    add eax, [rsp + 4]
    mov [rip + md_y], eax
    mov edi, [rip + md_cx0]
    mov esi, eax
    mov edx, [rip + tb_tw]
    add edx, [rip + g_border]
    mov ecx, [rip + g_border]
    COLOR r8d, T_BORDER
    call gfx_fill
    mov eax, [rip + g_border]
    add [rip + md_y], eax
    EPILOGUE

# table(p) -> the line after it. p is its header; the row of dashes under it says how the columns
#   are aligned. Columns are as wide as their widest cell, and narrower when the column has no room
table:
    PROLOGUE 48
    mov [rsp], rdi
    call line_end
    mov [rsp + 8], rax
    mov r13, rdx                # the row of dashes
    mov rdi, rdx
    call line_end
    mov r14, rax
    mov [rsp + 16], rdx
    # its rows go on until a line without a bar
    mov rbx, rdx
1:  cmp rbx, [rip + md_end]
    jae 2f
    mov rdi, rbx
    call line_end
    mov r15, rdx
    mov rdi, rbx
    mov rsi, rax
    mov edx, '|'
    call has_byte
    test eax, eax
    jz 2f
    mov rbx, r15
    jmp 1b
2:  mov [rsp + 24], rbx
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call row_parse
    mov [rip + tb_n], eax
    mov rdi, r13
    mov rsi, r14
    call row_parse
    mov r15d, eax
    xor ebx, ebx
3:  cmp ebx, TB_MAXC
    jae 5f
    lea rdx, [rip + tb_w]
    mov dword ptr [rdx + rbx*4], 0
    xor ecx, ecx
    cmp ebx, r15d
    jae 4f
    mov eax, ebx
    shl eax, 4
    lea rdx, [rip + tb_cell]
    mov rdi, [rdx + rax]
    mov rsi, [rdx + rax + 8]
    test rsi, rsi
    jz 4f
    cmp byte ptr [rdi + rsi - 1], ':'
    jne 4f
    mov ecx, 1
    cmp byte ptr [rdi], ':'
    jne 4f
    mov ecx, 2
4:  lea rdx, [rip + tb_al]
    mov [rdx + rbx*4], ecx
    inc ebx
    jmp 3b
5:  mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov edx, ST_BOLD
    call tb_measure_row
    mov rbx, [rsp + 16]
6:  cmp rbx, [rsp + 24]
    jae 7f
    mov rdi, rbx
    call line_end
    mov r15, rdx
    mov rdi, rbx
    mov rsi, rax
    xor edx, edx
    call tb_measure_row
    mov rbx, r15
    jmp 6b
7:  # with the room beside the text; all of them narrower when they are wider than the column
    M r12d, MI_12
    xor ebx, ebx
    xor r13d, r13d
8:  cmp ebx, [rip + tb_n]
    jae 9f
    lea rdx, [rip + tb_w]
    mov eax, [rdx + rbx*4]
    lea eax, [rax + r12*2]
    mov [rdx + rbx*4], eax
    add r13d, eax
    inc ebx
    jmp 8b
9:  cmp r13d, [rip + md_cw]
    jle .Ltb_fit
    mov edi, 48
    call sc
    mov r14d, eax
    xor ebx, ebx
    xor r15d, r15d
10: cmp ebx, [rip + tb_n]
    jae 12f
    lea rcx, [rip + tb_w]
    mov eax, [rcx + rbx*4]
    imul eax, [rip + md_cw]
    cdq
    idiv r13d
    cmp eax, r14d
    jge 11f
    mov eax, r14d
11: lea rcx, [rip + tb_w]
    mov [rcx + rbx*4], eax
    add r15d, eax
    inc ebx
    jmp 10b
12: mov r13d, r15d
.Ltb_fit:
    mov [rip + tb_tw], r13d
    mov edi, BK_TABLE
    call block_gap
    mov eax, [rip + md_y]
    mov [rip + tb_y0], eax
    mov edi, [rip + md_cx0]
    mov esi, eax
    mov edx, r13d
    add edx, [rip + g_border]
    mov ecx, [rip + g_border]
    COLOR r8d, T_BORDER
    call gfx_fill
    mov eax, [rip + g_border]
    add [rip + md_y], eax
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov edx, ST_BOLD
    call tb_row
    mov rbx, [rsp + 16]
13: cmp rbx, [rsp + 24]
    jae 14f
    mov rdi, rbx
    call line_end
    mov r15, rdx
    mov rdi, rbx
    mov rsi, rax
    xor edx, edx
    call tb_row
    mov rbx, r15
    jmp 13b
14: # the lines between the columns
    xor ebx, ebx
    mov r13d, [rip + md_cx0]
15: mov edi, r13d
    mov esi, [rip + tb_y0]
    mov edx, [rip + g_border]
    mov ecx, [rip + md_y]
    sub ecx, esi
    COLOR r8d, T_BORDER
    call gfx_fill
    cmp ebx, [rip + tb_n]
    jae 16f
    lea rcx, [rip + tb_w]
    add r13d, [rcx + rbx*4]
    inc ebx
    jmp 15b
16: mov dword ptr [rip + md_prev], BK_TABLE
    mov rax, [rsp + 24]
    EPILOGUE

# ---- text ----

# is_space_ch(byte) -> 1 for a blank or a line break
is_space_ch:
    xor eax, eax
    cmp edi, ' '
    je 1f
    cmp edi, 9
    je 1f
    cmp edi, 10
    je 1f
    cmp edi, 13
    jne 2f
1:  mov eax, 1
2:  ret

# is_punct(byte) -> 1 for ASCII punctuation: what a backslash can stand before
is_punct:
    xor eax, eax
    cmp edi, 33
    jb 2f
    cmp edi, 126
    ja 2f
    cmp edi, '0'
    jb 1f
    cmp edi, '9'
    jbe 2f
    cmp edi, 'A'
    jb 1f
    cmp edi, 'Z'
    jbe 2f
    cmp edi, 'a'
    jb 1f
    cmp edi, 'z'
    jbe 2f
1:  mov eax, 1
2:  ret

# is_url(p, end) -> 1 when the text starts as a link to the web or to mail
is_url:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    sub r13, rdi
    lea rbx, [rip + md_schemes]
1:  mov rdx, [rbx]
    xor eax, eax
    test rdx, rdx
    jz 2f
    mov rdi, r12
    mov rsi, r13
    mov rcx, [rbx + 8]
    call str_starts
    test eax, eax
    jnz 2f
    add rbx, 16
    jmp 1b
2:  EPILOGUE

# find_run(p, end, byte, n) -> 1 when n of the byte come again after p, at the end of text
find_run:
    inc rdi
1:  lea rax, [rdi + rcx]
    cmp rax, rsi
    ja 5f
    xor r9d, r9d
2:  cmp byte ptr [rdi + r9], dl
    jne 4f
    inc r9d
    cmp r9d, ecx
    jb 2b
    movzx eax, byte ptr [rdi - 1]
    cmp al, ' '
    je 4f
    cmp al, 10
    je 4f
    mov eax, 1
    ret
4:  inc rdi
    jmp 1b
5:  xor eax, eax
    ret

# link_parse(p, end) -> 1 when p starts [text](url): lp_close the ] of its text, lp_url and
#   lp_urllen, lp_after the text that follows it
link_parse:
    lea rax, [rdi + 1]
    mov ecx, 1
1:  cmp rax, rsi
    jae .Llp_no
    movzx edx, byte ptr [rax]
    cmp dl, '\\'
    jne 2f
    add rax, 2
    jmp 1b
2:  cmp dl, '['
    jne 3f
    inc ecx
    jmp 4f
3:  cmp dl, ']'
    jne 4f
    dec ecx
    jz 5f
4:  inc rax
    jmp 1b
5:  mov [rip + lp_close], rax
    inc rax
    cmp rax, rsi
    jae .Llp_no
    cmp byte ptr [rax], '('
    jne .Llp_no
    inc rax
    mov [rip + lp_url], rax
    xor ecx, ecx
6:  cmp rax, rsi
    jae .Llp_no
    movzx edx, byte ptr [rax]
    cmp dl, ')'
    jne 7f
    test ecx, ecx
    jz 11f
    dec ecx
    jmp 9f
7:  cmp dl, '('
    jne 8f
    inc ecx
    jmp 9f
8:  cmp dl, ' '
    je 10f
    cmp dl, 10
    je 10f
9:  inc rax
    jmp 6b
10: # a title after the address
    mov r8, rax
101: cmp rax, rsi
    jae .Llp_no
    cmp byte ptr [rax], ')'
    je 102f
    inc rax
    jmp 101b
102: mov rcx, r8
    jmp 12f
11: mov rcx, rax
12: sub rcx, [rip + lp_url]
    mov [rip + lp_urllen], rcx
    inc rax
    mov [rip + lp_after], rax
    mov eax, 1
    ret
.Llp_no:
    xor eax, eax
    ret

# tag_style(p, end) -> the style an HTML tag's name turns: b, strong, i, em; or 0
tag_style:
    PROLOGUE
    mov r12, rdi
    mov r13, rdi
1:  cmp r13, rsi
    jae 2f
    movzx eax, byte ptr [r13]
    or al, 0x20
    cmp al, 'a'
    jb 2f
    cmp al, 'z'
    ja 2f
    inc r13
    jmp 1b
2:  sub r13, r12
    lea rbx, [rip + md_tags]
3:  mov rdx, [rbx]
    xor eax, eax
    test rdx, rdx
    jz 4f
    mov rdi, r12
    mov rsi, r13
    mov rcx, [rbx + 8]
    call str_ieq
    test eax, eax
    jnz 5f
    add rbx, 24
    jmp 3b
5:  mov eax, [rbx + 16]
4:  EPILOGUE

# flow_break(): go on at the start of the next line
flow_break:
    mov eax, [rip + fl_lh]
    add [rip + md_y], eax
    mov eax, [rip + fl_x0]
    mov [rip + fl_x], eax
    mov dword ptr [rip + fl_any], 0
    mov dword ptr [rip + fl_space], 0
    mov dword ptr [rip + fl_lastst], 0
    ret

# word_byte(byte): one more byte of the word, in the styles that were on at its first
word_byte:
    mov ecx, [rip + fl_wlen]
    test ecx, ecx
    jnz 1f
    mov eax, [rip + fl_st]
    mov [rip + fl_wst], eax
    mov rax, [rip + fl_url]
    mov [rip + fl_wurl], rax
    mov rax, [rip + fl_urllen]
    mov [rip + fl_wurllen], rax
    jmp 3f
1:  cmp ecx, WBUF - 8
    jb 3f
    # a full buffer goes out between two characters
    cmp ecx, WBUF - 1
    jae 2f
    mov eax, edi
    and eax, 0xc0
    cmp eax, 0x80
    je 3f
2:  push rdi
    call word_flush
    pop rdi
    jmp word_byte
3:  lea rax, [rip + fl_wbuf]
    mov [rax + rcx], dil
    inc ecx
    mov [rip + fl_wlen], ecx
    ret

# hot_set(): the pointer is over the link of the piece being drawn
hot_set:
    push rbx
    mov rdx, [rip + fl_wurllen]
    test rdx, rdx
    jz 1f
    cmp rdx, HOT_MAX
    ja 1f
    mov [rip + md_hotlen], rdx
    lea rdi, [rip + md_hotbuf]
    mov rsi, [rip + fl_wurl]
    call memcpy
    mov dword ptr [rip + md_hot], 1
1:  pop rbx
    ret

# tok_draw(ptr, len, x, w, face): a piece of text on the current line, in the styles of fl_tst
tok_draw:
    PROLOGUE 48
    cmp dword ptr [rip + md_nodraw], 0
    jne .Ltk_ret
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    mov r15d, ecx
    mov rbx, r8
    mov eax, [rip + md_y]
    cmp eax, [rip + md_cy1]
    jge .Ltk_ret
    add eax, [rip + fl_lh]
    cmp eax, [rip + md_cy0]
    jle .Ltk_ret
    # the text in the middle of its line
    mov eax, [rip + fl_lh]
    sub eax, [rbx + FACE_ascent]
    sub eax, [rbx + FACE_descent]
    sar eax, 1
    add eax, [rip + md_y]
    mov [rsp + 4], eax
    add eax, [rbx + FACE_ascent]
    mov [rsp], eax              # baseline
    mov eax, [rip + fl_color]
    mov [rsp + 8], eax
    mov dword ptr [rsp + 12], 0 # underlined
    test dword ptr [rip + fl_tst], ST_CODE
    jz 1f
    M eax, MI_1
    mov edi, r14d
    mov esi, [rsp + 4]
    sub esi, eax
    mov edx, r15d
    mov ecx, [rbx + FACE_ascent]
    add ecx, [rbx + FACE_descent]
    lea ecx, [rcx + rax*2]
    M r8d, MI_3
    mov r9d, [rip + md_codebg]
    call gfx_round_rect
    mov eax, [rbx + FACE_px]
    shr eax, 2
    add r14d, eax
    sub r15d, eax
    sub r15d, eax
1:  test dword ptr [rip + fl_tst], ST_LINK
    jz 2f
    COLOR eax, T_SYN + C_LINK
    mov [rsp + 8], eax
    mov edi, r14d
    mov esi, [rip + md_y]
    mov edx, r15d
    mov ecx, [rip + fl_lh]
    call ui_in
    test eax, eax
    jz 2f
    mov dword ptr [rsp + 12], 1
    call hot_set
2:  mov rdi, rbx
    mov esi, r14d
    add esi, [rip + fl_lead]
    mov edx, [rsp]
    mov rcx, r12
    mov r8, r13
    mov r9d, [rsp + 8]
    call text_draw
    test dword ptr [rip + fl_tst], ST_BOLD
    jz 4f
    # there is no bold face: the text again, a little to the right
    mov eax, [rbx + FACE_px]
    add eax, 8
    shr eax, 4
    cmp eax, 1
    jge 3f
    mov eax, 1
3:  mov rdi, rbx
    lea esi, [r14 + rax]
    add esi, [rip + fl_lead]
    mov edx, [rsp]
    mov rcx, r12
    mov r8, r13
    mov r9d, [rsp + 8]
    call text_draw
4:  test dword ptr [rip + fl_tst], ST_STRIKE
    jz 5f
    mov eax, [rbx + FACE_ascent]
    lea eax, [rax + rax*4]
    shr eax, 4
    mov edi, r14d
    mov esi, [rsp]
    sub esi, eax
    mov edx, r15d
    mov ecx, [rip + g_border]
    mov r8d, [rsp + 8]
    call gfx_fill
5:  cmp dword ptr [rsp + 12], 0
    je .Ltk_ret
    M eax, MI_2
    mov edi, r14d
    mov esi, [rsp]
    add esi, eax
    mov edx, r15d
    mov ecx, [rip + g_border]
    mov r8d, [rsp + 8]
    call gfx_fill
.Ltk_ret:
    EPILOGUE

# word_flush(): put the word in the buffer on the line, on the next one when it has no room, and in
#   pieces when it is wider than a line
word_flush:
    PROLOGUE 48
    mov r13d, [rip + fl_wlen]
    test r13d, r13d
    jz .Lwf_ret
    lea r12, [rip + fl_wbuf]
    mov r14d, [rip + fl_wst]
    or r14d, [rip + fl_base]
    # an address written out is a link to it
    test r14d, ST_LINK | ST_CODE
    jnz 3f
    mov rdi, r12
    lea rsi, [r12 + r13]
    call is_url
    test eax, eax
    jz 3f
    or r14d, ST_LINK
    mov [rip + fl_wurl], r12
    mov rcx, r13
1:  cmp rcx, 1                  # less the punctuation of the sentence around it
    jbe 2f
    movzx eax, byte ptr [r12 + rcx - 1]
    cmp al, '.'
    je 11f
    cmp al, ','
    je 11f
    cmp al, ')'
    je 11f
    cmp al, ';'
    je 11f
    cmp al, ':'
    jne 2f
11: dec rcx
    jmp 1b
2:  mov [rip + fl_wurllen], rcx
3:  mov [rip + fl_tst], r14d
    mov rbx, [rip + fl_face]
    test r14d, ST_ITALIC
    jz 4f
    lea rax, [rip + g_face_code]
    cmp rbx, rax
    jne 4f
    lea rbx, [rip + md_face_it]
4:  xor r15d, r15d              # room beside code
    test r14d, ST_CODE
    jz .Lwf_again
    mov r15d, [rbx + FACE_px]
    shr r15d, 2
.Lwf_again:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call text_width
    lea eax, [rax + r15*2]
    mov [rsp], eax              # its width
    xor ecx, ecx
    cmp dword ptr [rip + fl_space], 0
    je 5f
    cmp dword ptr [rip + fl_any], 0
    je 5f
    mov ecx, [rbx + FACE_cellw]
5:  mov [rsp + 4], ecx          # the blank before it
    mov edx, [rip + fl_x]
    add edx, ecx
    add edx, eax
    cmp edx, [rip + fl_x1]
    jle .Lwf_place
    cmp dword ptr [rip + fl_any], 0
    je .Lwf_wide
    # a short piece that touches the word before it stays with it
    cmp dword ptr [rip + fl_space], 0
    jne 6f
    mov ecx, [rbx + FACE_cellw]
    add ecx, ecx
    cmp eax, ecx
    jle .Lwf_place
6:  call flow_break
    jmp .Lwf_again
.Lwf_wide:
    mov ecx, [rip + fl_x1]
    sub ecx, [rip + fl_x]
    sub ecx, r15d
    sub ecx, r15d
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call text_fit
    test rax, rax
    jnz 7f
    mov rdi, r12
    mov rsi, r13
    call utf8_decode
    mov eax, edx
7:  cmp rax, r13
    jae .Lwf_place
    mov [rsp + 8], rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rax
    call text_width
    lea ecx, [rax + r15*2]
    mov rdi, r12
    mov rsi, [rsp + 8]
    mov edx, [rip + fl_x]
    mov r8, rbx
    mov dword ptr [rip + fl_lead], 0
    call tok_draw
    mov eax, [rip + fl_x1]
    cmp eax, [rip + fl_maxx]
    jle 8f
    mov [rip + fl_maxx], eax
8:  call flow_break
    mov rax, [rsp + 8]
    add r12, rax
    sub r13, rax
    jmp .Lwf_again
.Lwf_place:
    # the blank between two words of one link, or of struck text, is theirs
    xor eax, eax
    xor ecx, ecx
    test r14d, ST_CODE
    jnz 82f
    mov ecx, r14d
    and ecx, ST_LINK | ST_STRIKE
    jz 82f
    cmp ecx, [rip + fl_lastst]
    jne 82f
    test ecx, ST_LINK
    jz 81f
    mov rdx, [rip + fl_wurl]
    cmp rdx, [rip + fl_lasturl]
    jne 82f
    cmp rdx, r12                # an address written out is its own
    je 82f
81: mov eax, [rsp + 4]
82: mov [rip + fl_lead], eax
    mov [rip + fl_lastst], ecx
    mov rdx, [rip + fl_wurl]
    mov [rip + fl_lasturl], rdx
    mov edx, [rip + fl_x]
    add edx, [rsp + 4]
    sub edx, eax
    mov rdi, r12
    mov rsi, r13
    mov ecx, [rsp]
    add ecx, eax
    mov r8, rbx
    call tok_draw
    mov eax, [rip + fl_x]
    add eax, [rsp + 4]
    add eax, [rsp]
    mov [rip + fl_x], eax
    cmp eax, [rip + fl_maxx]
    jle 9f
    mov [rip + fl_maxx], eax
9:  mov dword ptr [rip + fl_any], 1
    mov dword ptr [rip + fl_space], 0
    mov dword ptr [rip + fl_wlen], 0
.Lwf_ret:
    EPILOGUE

# flow(ptr, len) -> eax how wide the text ran: a block's text set between fl_x0 and fl_x1 from md_y
#   down, in fl_face and fl_color. Its marks give the styles: `code`, *slanted*, **bold**,
#   ~~struck~~, [links](to), <tags> left out. md_y ends under the last line
flow:
    PROLOGUE 32
    mov r12, rdi
    lea r13, [rdi + rsi]
    mov r14, rdi
    mov dword ptr [rip + fl_st], 0
    mov dword ptr [rip + fl_wlen], 0
    mov dword ptr [rip + fl_space], 0
    mov dword ptr [rip + fl_any], 0
    mov dword ptr [rip + fl_lastst], 0
    mov qword ptr [rip + fl_linkend], 0
    mov qword ptr [rip + fl_codeend], 0
    mov eax, [rip + fl_x0]
    mov [rip + fl_x], eax
    mov [rip + fl_maxx], eax
.Lf_loop:
    cmp r12, r13
    jae .Lf_done
    movzx eax, byte ptr [r12]
    # in a code span everything is text, up to its closing marks
    mov rcx, [rip + fl_codeend]
    test rcx, rcx
    jz .Lf_text
    cmp r12, rcx
    jne 1f
    call word_flush
    and dword ptr [rip + fl_st], ~ST_CODE
    mov eax, [rip + fl_codeticks]
    add r12, rax
    mov qword ptr [rip + fl_codeend], 0
    jmp .Lf_loop
1:  cmp al, 10
    jne 2f
    mov eax, ' '
2:  mov edi, eax
    call word_byte
    inc r12
    jmp .Lf_loop
.Lf_text:
    cmp r12, [rip + fl_linkend]
    jne 1f
    call word_flush
    and dword ptr [rip + fl_st], ~ST_LINK
    mov r12, [rip + fl_linkafter]
    mov qword ptr [rip + fl_linkend], 0
    jmp .Lf_loop
1:  cmp al, ' '
    je .Lf_blank
    cmp al, 9
    je .Lf_blank
    cmp al, 13
    je .Lf_blank
    cmp al, 10
    jne .Lf_mark
    # a quote's next line starts with its mark again
    inc r12
    test dword ptr [rip + fl_opt], FO_QUOTE
    jz .Lf_word
2:  cmp r12, r13
    jae .Lf_word
    cmp byte ptr [r12], ' '
    jne 3f
    inc r12
    jmp 2b
3:  cmp byte ptr [r12], '>'
    jne .Lf_word
    inc r12
    jmp .Lf_word
.Lf_blank:
    inc r12
.Lf_word:
    call word_flush
    mov dword ptr [rip + fl_space], 1
    jmp .Lf_loop
.Lf_mark:
    cmp al, '\\'
    jne 1f
    lea rcx, [r12 + 1]
    cmp rcx, r13
    jae .Lf_lit
    movzx edi, byte ptr [rcx]
    call is_punct
    test eax, eax
    jz .Lf_lit
    movzx edi, byte ptr [r12 + 1]
    call word_byte
    add r12, 2
    jmp .Lf_loop
1:  cmp al, '`'
    je .Lf_tick
    cmp al, '*'
    je .Lf_emph
    cmp al, '_'
    je .Lf_emph
    cmp al, '~'
    je .Lf_strike
    cmp al, '['
    je .Lf_link
    cmp al, '!'
    je .Lf_image
    cmp al, '<'
    je .Lf_angle
    cmp al, '&'
    je .Lf_entity
.Lf_lit:
    movzx edi, byte ptr [r12]
    call word_byte
    inc r12
    jmp .Lf_loop

.Lf_tick:
    mov rdi, r12
    mov rsi, r13
    mov edx, '`'
    call run_of
    mov ebx, eax
    lea r15, [r12 + rbx]
1:  cmp r15, r13
    jae 4f
    cmp byte ptr [r15], '`'
    je 2f
    inc r15
    jmp 1b
2:  mov rdi, r15
    mov rsi, r13
    mov edx, '`'
    call run_of
    cmp eax, ebx
    je 3f
    add r15, rax
    jmp 1b
3:  call word_flush
    or dword ptr [rip + fl_st], ST_CODE
    mov [rip + fl_codeend], r15
    mov [rip + fl_codeticks], ebx
    add r12, rbx
    jmp .Lf_loop
4:  mov edi, '`'                # no closing marks: they are text
    call word_byte
    inc r12
    dec ebx
    jnz 4b
    jmp .Lf_loop

.Lf_emph:
    mov [rsp], eax              # the mark
    mov rdi, r12
    mov rsi, r13
    mov edx, eax
    call run_of
    mov ebx, eax
    cmp ebx, 3
    ja .Lf_run
    # what stands before and after the marks
    mov ecx, ' '
    cmp r12, r14
    jbe 1f
    movzx ecx, byte ptr [r12 - 1]
1:  mov [rsp + 4], ecx
    mov ecx, ' '
    lea rax, [r12 + rbx]
    cmp rax, r13
    jae 2f
    movzx ecx, byte ptr [rax]
2:  mov [rsp + 8], ecx
    mov r15d, ST_ITALIC
    cmp ebx, 1
    je 3f
    mov r15d, ST_BOLD
    cmp ebx, 2
    je 3f
    mov r15d, ST_BOLD | ST_ITALIC
3:  # they close what is on, after text
    mov eax, [rip + fl_st]
    and eax, r15d
    cmp eax, r15d
    jne 5f
    mov edi, [rsp + 4]
    call is_space_ch
    test eax, eax
    jnz 5f
    cmp dword ptr [rsp], '_'
    jne 4f
    mov edi, [rsp + 8]
    call is_ident
    test eax, eax
    jnz .Lf_run
4:  call word_flush
    not r15d
    and [rip + fl_st], r15d
    add r12, rbx
    jmp .Lf_loop
5:  # or open, before text, when they come again further on
    test [rip + fl_st], r15d
    jnz .Lf_run
    mov edi, [rsp + 8]
    call is_space_ch
    test eax, eax
    jnz .Lf_run
    cmp dword ptr [rsp], '_'
    jne 6f
    mov edi, [rsp + 4]
    call is_ident
    test eax, eax
    jnz .Lf_run
6:  lea rdi, [r12 + rbx]
    mov rsi, r13
    mov edx, [rsp]
    mov ecx, ebx
    call find_run
    test eax, eax
    jz .Lf_run
    call word_flush
    or [rip + fl_st], r15d
    add r12, rbx
    jmp .Lf_loop
.Lf_run:
    mov edi, [rsp]              # marks that mark nothing
    call word_byte
    inc r12
    dec ebx
    jnz .Lf_run
    jmp .Lf_loop

.Lf_strike:
    lea rax, [r12 + 1]
    cmp rax, r13
    jae .Lf_lit
    cmp byte ptr [rax], '~'
    jne .Lf_lit
    test dword ptr [rip + fl_st], ST_STRIKE
    jz 1f
    call word_flush
    and dword ptr [rip + fl_st], ~ST_STRIKE
    add r12, 2
    jmp .Lf_loop
1:  lea rdi, [r12 + 2]
    mov rsi, r13
    mov edx, '~'
    mov ecx, 2
    call find_run
    test eax, eax
    jz .Lf_lit
    call word_flush
    or dword ptr [rip + fl_st], ST_STRIKE
    add r12, 2
    jmp .Lf_loop

.Lf_image:
    # ![what it shows](file): its words, as a link to the file
    lea rdi, [r12 + 1]
    cmp rdi, r13
    jae .Lf_lit
    cmp byte ptr [rdi], '['
    jne .Lf_lit
    mov rsi, r13
    call link_parse
    test eax, eax
    jz .Lf_lit
    inc r12
    cmp qword ptr [rip + fl_linkend], 0
    je .Lf_golink
    # inside a link the words are the link's
    inc r12
1:  cmp r12, [rip + lp_close]
    jae 3f
    movzx edi, byte ptr [r12]
    inc r12
    cmp edi, ' '
    jne 2f
    call word_flush
    mov dword ptr [rip + fl_space], 1
    jmp 1b
2:  call word_byte
    jmp 1b
3:  mov r12, [rip + lp_after]
    jmp .Lf_loop
.Lf_link:
    cmp qword ptr [rip + fl_linkend], 0
    jne .Lf_lit
    mov rdi, r12
    mov rsi, r13
    call link_parse
    test eax, eax
    jz .Lf_lit
.Lf_golink:
    call word_flush
    or dword ptr [rip + fl_st], ST_LINK
    mov rax, [rip + lp_close]
    mov [rip + fl_linkend], rax
    mov rax, [rip + lp_after]
    mov [rip + fl_linkafter], rax
    mov rax, [rip + lp_url]
    mov [rip + fl_url], rax
    mov rax, [rip + lp_urllen]
    mov [rip + fl_urllen], rax
    inc r12
    jmp .Lf_loop

.Lf_angle:
    mov rbx, r13
    sub rbx, r12
    cmp rbx, 4
    jb .Lf_tag
    cmp dword ptr [r12], 0x2d2d213c     # <!--
    jne .Lf_auto
    lea r15, [r12 + 4]
1:  lea rax, [r15 + 3]
    cmp rax, r13
    ja 3f
    cmp byte ptr [r15], '-'
    jne 2f
    cmp byte ptr [r15 + 1], '-'
    jne 2f
    cmp byte ptr [r15 + 2], '>'
    jne 2f
    lea r12, [r15 + 3]
    jmp .Lf_loop
2:  inc r15
    jmp 1b
3:  mov r12, r13
    jmp .Lf_loop
.Lf_auto:
    # <https://...>
    cmp qword ptr [rip + fl_linkend], 0
    jne .Lf_tag
    lea rdi, [r12 + 1]
    mov rsi, r13
    call is_url
    test eax, eax
    jz .Lf_tag
    lea r15, [r12 + 1]
1:  cmp r15, r13
    jae .Lf_lit
    movzx eax, byte ptr [r15]
    cmp al, '>'
    je 2f
    cmp al, ' '
    je .Lf_lit
    cmp al, 10
    je .Lf_lit
    inc r15
    jmp 1b
2:  call word_flush
    or dword ptr [rip + fl_st], ST_LINK
    lea rax, [r12 + 1]
    mov [rip + fl_url], rax
    mov rcx, r15
    sub rcx, rax
    mov [rip + fl_urllen], rcx
    mov [rip + fl_linkend], r15
    lea rax, [r15 + 1]
    mov [rip + fl_linkafter], rax
    inc r12
    jmp .Lf_loop
.Lf_tag:
    # an HTML tag is left out; <br> breaks the line, <b> and <i> turn their styles
    cmp rbx, 3
    jb .Lf_lit
    movzx eax, byte ptr [r12 + 1]
    cmp al, '/'
    je 1f
    or al, 0x20
    cmp al, 'a'
    jb .Lf_lit
    cmp al, 'z'
    ja .Lf_lit
1:  lea r15, [r12 + 1]
2:  cmp r15, r13
    jae .Lf_lit
    cmp byte ptr [r15], '>'
    je 3f
    inc r15
    jmp 2b
3:  call word_flush
    lea rdi, [r12 + 1]
    xor ebx, ebx                # closing
    cmp byte ptr [rdi], '/'
    jne 4f
    inc rdi
    mov ebx, 1
4:  mov rsi, r15
    call tag_style
    cmp eax, -1
    jne 5f
    call flow_break
    jmp 7f
5:  test ebx, ebx
    jnz 6f
    or [rip + fl_st], eax
    jmp 7f
6:  not eax
    and [rip + fl_st], eax
7:  lea r12, [r15 + 1]
    jmp .Lf_loop

.Lf_entity:
    lea r15, [rip + md_entities]
1:  mov rsi, [r15]
    test rsi, rsi
    jz .Lf_lit
    mov rdx, [r15 + 8]
    mov rax, r13
    sub rax, r12
    cmp rax, rdx
    jb 2f
    mov rdi, r12
    call memeq
    test eax, eax
    jz 2f
    mov edi, [r15 + 16]
    call word_byte
    add r12, [r15 + 8]
    jmp .Lf_loop
2:  add r15, 24
    jmp 1b

.Lf_done:
    call word_flush
    cmp dword ptr [rip + fl_any], 0
    je 1f
    mov eax, [rip + fl_lh]
    add [rip + md_y], eax
1:  mov eax, [rip + fl_maxx]
    sub eax, [rip + fl_x0]
    EPILOGUE

.section .rodata
.Ls_markdown: .asciz "Markdown"
.Ls_preview: .asciz "Preview"
.Ls_edit: .asciz "Edit"
.Ls_state: .asciz " preview=1"
.Lu_http: .ascii "http://"
.Lu_https: .ascii "https://"
.Lu_mailto: .ascii "mailto:"
.Le_amp: .ascii "&amp;"
.Le_lt: .ascii "&lt;"
.Le_gt: .ascii "&gt;"
.Le_quot: .ascii "&quot;"
.Le_apos: .ascii "&#39;"
.Le_nbsp: .ascii "&nbsp;"
.Lt_b: .ascii "b"
.Lt_strong: .ascii "strong"
.Lt_i: .ascii "i"
.Lt_em: .ascii "em"
.Lt_br: .ascii "br"
.p2align 3
md_schemes:
    .quad .Lu_http, 7, .Lu_https, 8, .Lu_mailto, 7, 0, 0
# name, length, the character it stands for
md_entities:
    .quad .Le_amp, 5, '&', .Le_lt, 4, '<', .Le_gt, 4, '>', .Le_quot, 6, '"'
    .quad .Le_apos, 5, 39, .Le_nbsp, 6, ' ', 0, 0, 0
# name, length, style (-1: a line break)
md_tags:
    .quad .Lt_b, 1, ST_BOLD, .Lt_strong, 6, ST_BOLD, .Lt_i, 1, ST_ITALIC, .Lt_em, 2, ST_ITALIC
    .quad .Lt_br, 2, -1, 0, 0, 0
