# markdown preview: a Markdown file drawn as a page in place of its text (DF_PREVIEW), from the
# buffer as it is, unsaved edits included. A switch in the pane's corner goes between the two.
.include "raftaar.inc"

.equ ID_MD_PREVIEW, 0x4d01
.equ ID_MD_EDIT, 0x4d02
.equ ID_MD_SCROLL, 0x4d03
.equ ID_MD_PAGE, 0x4d04           # a selection being dragged
.equ ID_MD_COPY, 0x4e00           # + the code block's number: its Copy button
.equ CLS_MAX, 4096               # longest line of code colored

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
.equ LW_MAX, 256                # lines of a centered block that are centered

# a picture of the page, read once: as it is, or made smaller to the widest the column gets
STRUCT
F IC_path, 8
F IC_px, 8              # premultiplied ARGB, sw * sh; 0 when the file is not a picture
F IC_nw, 4              # the picture's own size
F IC_nh, 4
F IC_sw, 4
F IC_sh, 4
ENDSTRUCT IC_SIZE
.equ IC_MAX, 16

.bss
.p2align 3
md_face_sl: .zero FACE_SIZE     # the text's face, slanted: italics where there is no italic font
md_face_b: .zero FACE_SIZE      # bold, italic, both: in the order of ST_BOLD | ST_ITALIC
md_face_i: .zero FACE_SIZE
md_face_bi: .zero FACE_SIZE
md_face_h1: .zero FACE_SIZE     # headings, bold
md_face_h2: .zero FACE_SIZE
md_face_h3: .zero FACE_SIZE
md_face_h1r: .zero FACE_SIZE    # and from the regular font, for text the bold one has not
md_face_h2r: .zero FACE_SIZE
md_face_h3r: .zero FACE_SIZE
md_font_b: .quad 0              # the built-in bold, italic and bold italic fonts
md_font_i: .quad 0
md_font_bi: .quad 0
md_fontkey: .quad 0             # the font the faces were made for
md_doc: .quad 0
md_end: .quad 0                 # end of the text
md_sb: .zero SB_SIZE
md_copy_sb: .zero SB_SIZE       # the selected text, gathered for the clipboard
sel_doc: .quad 0                # the document the selection is in
cb_start: .quad 0               # the code block: its first line, its grammar
cb_gr: .quad 0
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
md_synth: .long 0               # another font is set: bold is drawn twice over, italics slanted
fl_twice: .long 0               # the piece being drawn is bold without a bold face
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
cb_state: .long 0               # the tokenizer's state at the next line
cb_y0: .long 0
cb_idx: .long 0                 # code blocks so far on the page
cb_copy: .long 0                # the block whose Copy was pressed
md_copied: .long 0              # the block that says Copied
md_btn_hit: .long 0             # the press was a button's
sel_ax: .long 0                 # the selection: from where the press was to the pointer, in the
sel_ay: .long 0                 #   page: x from the column's edge, y from the page's top
sel_cx: .long 0
sel_cy: .long 0
sel_has: .long 0
sel_pass: .long 0               # this page has it: ss_* to se_* on the screen, in reading order
ss_x: .long 0
ss_y: .long 0
se_x: .long 0
se_y: .long 0
sel_lasty: .long 0              # the line the last gathered piece was on
sel_soft: .long 0               # lines since the block's first are the same text, wrapped
md_collect: .long 0             # gather the selected text this frame
fl_gap: .long 0                 # the blank before the piece being drawn
fl_center: .long 0              # a centered block: 1 its lines' widths are being noted, 2 used
fl_line: .long 0
img_n: .long 0
fl_lw: .zero LW_MAX * 4
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
cb_label: .zero 32
.p2align 3
img_cache: .zero IC_MAX * IC_SIZE
cb_name: .zero 40
cb_cls: .zero CLS_MAX
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

# md_first(doc) -> 1 for a Markdown file. It starts as a page
md_first:
    push rbx
    mov rbx, rdi
    call md_is
    test eax, eax
    jz 1f
    test dword ptr [rbx + DOC_flags], DF_MDSEEN
    jnz 1f
    or dword ptr [rbx + DOC_flags], DF_MDSEEN | DF_PREVIEW
1:  pop rbx
    ret

# md_active() -> 1 while the document with the keys is shown as a page
FN md_active
    mov rdi, [rip + g_doc]
    xor eax, eax
    test rdi, rdi
    jz 1f
    call md_first
    xor eax, eax
    mov rcx, [rip + g_doc]
    test dword ptr [rcx + DOC_flags], DF_PREVIEW
    setnz al
1:  ret

FN cmd_toggle_md_preview
    push rbx
    mov rbx, [rip + g_doc]
    mov rdi, rbx
    call md_first
    test eax, eax
    jz 1f
    xor dword ptr [rbx + DOC_flags], DF_PREVIEW
    mov dword ptr [rip + g_dirty], 1
1:  pop rbx
    ret

# md_copy(): the page's selected text to the clipboard, gathered as the next frame draws it
FN md_copy
    mov rax, [rip + g_doc]
    cmp rax, [rip + sel_doc]
    jne 1f
    cmp dword ptr [rip + sel_has], 0
    je 1f
    mov dword ptr [rip + md_collect], 1
    mov dword ptr [rip + g_dirty], 1
1:  ret

# md_select_all(): the whole page
FN md_select_all
    mov rax, [rip + g_doc]
    mov [rip + sel_doc], rax
    mov dword ptr [rip + sel_ax], -0x100000
    mov dword ptr [rip + sel_ay], -0x100000
    mov dword ptr [rip + sel_cx], 0x100000
    mov dword ptr [rip + sel_cy], 0x3fffffff
    mov dword ptr [rip + sel_has], 1
    mov dword ptr [rip + g_dirty], 1
    ret

# md_describe(doc, sb): " preview=1" for a page (print-state)
FN md_describe
    push rdi
    push rsi
    call md_first
    pop rsi
    pop rdi
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
    cmp edi, KEY_ESCAPE
    jne 11f
    mov dword ptr [rip + sel_has], 0
    jmp .Lmk_used
11: cmp edi, KEY_HOME
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
    call md_first
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
    mov edx, 8
    call text_width
    M ecx, MI_10
    lea eax, [rax + rcx*2]
    mov [rip + tg_w1], eax
    lea rdi, [rip + g_face_small]
    lea rsi, [rip + .Ls_edit]
    mov edx, 3
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

# md_faces(): the page's faces, for the size and font of the editor's text. With the built-in font
#   bold and italics have fonts of their own; with another one they are made from it
md_faces:
    PROLOGUE
    mov ebx, [rip + g_face_code + FACE_px]
    mov r12, [rip + g_font_code]
    cmp ebx, [rip + md_px]
    jne 1f
    cmp r12, [rip + md_fontkey]
    je .Lmf_lh
1:  mov [rip + md_px], ebx
    mov [rip + md_fontkey], r12
    cmp qword ptr [rip + md_font_b], 0
    jne 2f
    lea rdi, [rip + font_bold]
    lea rsi, [rip + font_bold_end]
    sub rsi, rdi
    call font_load
    mov [rip + md_font_b], rax
    lea rdi, [rip + font_italic]
    lea rsi, [rip + font_italic_end]
    sub rsi, rdi
    call font_load
    mov [rip + md_font_i], rax
    lea rdi, [rip + font_bolditalic]
    lea rsi, [rip + font_bolditalic_end]
    sub rsi, rdi
    call font_load
    mov [rip + md_font_bi], rax
2:  mov eax, 1
    mov rcx, [rip + cfg_font]
    cmp byte ptr [rcx], 0
    jne 3f
    cmp qword ptr [rip + md_font_b], 0
    je 3f
    cmp qword ptr [rip + md_font_i], 0
    je 3f
    cmp qword ptr [rip + md_font_bi], 0
    je 3f
    xor eax, eax
3:  mov [rip + md_synth], eax
    lea rdi, [rip + md_face_sl]
    mov rsi, r12
    mov edx, ebx
    call face_init
    mov dword ptr [rip + md_face_sl + FACE_slant], 1
    mov r13, r12                # the headings' font
    cmp dword ptr [rip + md_synth], 0
    jne 4f
    mov r13, [rip + md_font_b]
    lea rdi, [rip + md_face_b]
    mov rsi, r13
    mov edx, ebx
    call face_init
    lea rdi, [rip + md_face_i]
    mov rsi, [rip + md_font_i]
    mov edx, ebx
    call face_init
    lea rdi, [rip + md_face_bi]
    mov rsi, [rip + md_font_bi]
    mov edx, ebx
    call face_init
4:  lea r14d, [rbx + rbx]
    lea rdi, [rip + md_face_h1]
    mov rsi, r13
    mov edx, r14d
    call face_init
    lea rdi, [rip + md_face_h1r]
    mov rsi, r12
    mov edx, r14d
    call face_init
    lea r14d, [rbx + rbx*2]
    shr r14d, 1
    lea rdi, [rip + md_face_h2]
    mov rsi, r13
    mov edx, r14d
    call face_init
    lea rdi, [rip + md_face_h2r]
    mov rsi, r12
    mov edx, r14d
    call face_init
    lea r14d, [rbx + rbx*4]
    shr r14d, 2
    lea rdi, [rip + md_face_h3]
    mov rsi, r13
    mov edx, r14d
    call face_init
    lea rdi, [rip + md_face_h3r]
    mov rsi, r12
    mov edx, r14d
    call face_init
.Lmf_lh:
    # prose has more room between its lines than code
    mov eax, ebx
    shr eax, 2
    add eax, [rip + g_lh]
    mov [rip + md_lh], eax
    EPILOGUE

# pick_face(styles, ptr, len) -> rax the face for a piece of text in fl_face; fl_twice says whether
#   its bold is still to be made by drawing it twice
pick_face:
    mov rax, [rip + fl_face]
    mov dword ptr [rip + fl_twice], 0
    # text the bold and italic fonts have not: beyond Latin
    mov ecx, [rip + md_synth]
1:  test rdx, rdx
    jz 2f
    cmp byte ptr [rsi], 0xc6
    jae 11f
    inc rsi
    dec rdx
    jmp 1b
11: mov ecx, 1
2:  lea r8, [rip + g_face_code]
    cmp rax, r8
    jne 5f
    test ecx, ecx
    jnz 3f
    mov edx, edi
    and edx, ST_BOLD | ST_ITALIC
    jz 9f
    dec edx
    imul rdx, rdx, FACE_SIZE
    lea rax, [rip + md_face_b]
    add rax, rdx
    ret
3:  test edi, ST_ITALIC
    jz 4f
    lea rax, [rip + md_face_sl]
4:  and edi, ST_BOLD
    mov [rip + fl_twice], edi
    ret
5:  # a heading
    test edi, ST_BOLD
    jz 9f
    test ecx, ecx
    jz 9f
    mov dword ptr [rip + fl_twice], 1
    cmp dword ptr [rip + md_synth], 0
    jne 9f
    add rax, 3 * FACE_SIZE      # its regular twin
9:  ret

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
    mov dword ptr [rip + cb_idx], 0
    mov dword ptr [rip + md_btn_hit], 0
    mov dword ptr [rip + sel_pass], 0
    # a selection being dragged ends at the pointer; past the view's edge the page follows
    cmp dword ptr [rip + g_active], ID_MD_PAGE
    jne .Lmd_sel
    cmp [rip + sel_doc], rbx
    jne .Lmd_sel
    test dword ptr [rip + g_mdown], 1 << BTN_LEFT
    jz .Lmd_sel
    M ecx, MI_12
    mov eax, [rip + g_my]
    cmp eax, [rsp + 4]
    jge 4f
    sub [rbx + DOC_mdscroll], ecx
    mov dword ptr [rip + g_dirty], 1
4:  mov edx, [rsp + 4]
    add edx, [rsp + 12]
    cmp eax, edx
    jl 5f
    add [rbx + DOC_mdscroll], ecx
    mov dword ptr [rip + g_dirty], 1
5:  mov rdi, rbx
    mov esi, [rsp + 12]
    call md_clamp
    mov eax, [rip + g_mx]
    sub eax, [rip + md_cx0]
    mov [rip + sel_cx], eax
    mov ecx, [rip + g_my]
    sub ecx, [rsp + 4]
    add ecx, [rbx + DOC_mdscroll]
    mov [rip + sel_cy], ecx
    cmp eax, [rip + sel_ax]
    jne 6f
    cmp ecx, [rip + sel_ay]
    je .Lmd_sel
6:  mov dword ptr [rip + sel_has], 1
.Lmd_sel:
    cmp [rip + sel_doc], rbx
    jne 9f
    cmp dword ptr [rip + sel_has], 0
    je 9f
    mov eax, [rip + sel_ax]
    mov ecx, [rip + sel_ay]
    mov edx, [rip + sel_cx]
    mov esi, [rip + sel_cy]
    cmp ecx, esi
    jl 8f
    jg 7f
    cmp eax, edx
    jle 8f
7:  mov r8d, eax                # the press was after the pointer
    mov eax, edx
    mov edx, r8d
    mov r8d, ecx
    mov ecx, esi
    mov esi, r8d
8:  add eax, [rip + md_cx0]
    mov [rip + ss_x], eax
    add edx, [rip + md_cx0]
    mov [rip + se_x], edx
    mov edi, [rsp + 4]
    sub edi, [rbx + DOC_mdscroll]
    add ecx, edi
    mov [rip + ss_y], ecx
    add esi, edi
    mov [rip + se_y], esi
    mov dword ptr [rip + sel_pass], 1
9:  cmp dword ptr [rip + md_collect], 0
    je 10f
    lea rdi, [rip + md_copy_sb]
    call sb_clear
10: mov edi, 24
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
2:  # the selected text, gathered
    cmp dword ptr [rip + md_collect], 0
    je 21f
    mov dword ptr [rip + md_collect], 0
    mov rdi, [rip + md_copy_sb + SB_ptr]
    mov rsi, [rip + md_copy_sb + SB_len]
    test rsi, rsi
    jz 21f
    xor edx, edx
    call ed_clip_set
21: # the pointer: a hand on a link, else the text's; a press follows the link or starts a selection
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    M eax, MI_12
    sub edx, eax
    mov ecx, [rsp + 12]
    call ui_in
    test eax, eax
    jz 3f
    cmp dword ptr [rip + md_hot], 0
    je 22f
    mov dword ptr [rip + g_cursor], CUR_POINTER
    jmp 23f
22: cmp dword ptr [rip + g_cursor], CUR_DEFAULT
    jne 23f
    mov dword ptr [rip + g_cursor], CUR_TEXT
23: test dword ptr [rip + g_pressed], 1 << BTN_LEFT
    jz 3f
    cmp dword ptr [rip + md_btn_hit], 0
    jne 3f
    cmp dword ptr [rip + md_hot], 0
    je 24f
    call md_open_link
    jmp 3f
24: mov [rip + sel_doc], rbx
    mov eax, [rip + g_mx]
    sub eax, [rip + md_cx0]
    mov [rip + sel_ax], eax
    mov [rip + sel_cx], eax
    mov eax, [rip + g_my]
    sub eax, [rsp + 4]
    add eax, [rbx + DOC_mdscroll]
    mov [rip + sel_ay], eax
    mov [rip + sel_cy], eax
    mov dword ptr [rip + sel_has], 0
    mov dword ptr [rip + g_active], ID_MD_PAGE
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
2:  mov rdi, r12
    mov rsi, rcx
    call md_path
    test rax, rax
    jz .Lol_ret
    mov rbx, rax
    # only a file that is there: a tab for a missing one would be a new file
    mov rdi, rax
    xor esi, esi
    SYS SYS_access
    test eax, eax
    jnz .Lol_ret
    mov rdi, rbx
    call app_open_file
.Lol_ret:
    EPILOGUE

# md_path(ptr, len) -> the file a link or a picture names, as a path in md_sb: from the folder of
#   the Markdown file unless it starts at the root; 0 without one
md_path:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor eax, eax
    test r13, r13
    jz 5f
    lea rdi, [rip + md_sb]
    call sb_clear
    cmp byte ptr [r12], '/'
    je 4f
    mov rbx, [rip + md_doc]
    mov rbx, [rbx + DOC_path]
    xor eax, eax
    test rbx, rbx
    jz 5f
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
3:  cmp r13, 2                  # ./ says nothing
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
    mov rax, [rip + md_sb + SB_ptr]
5:  EPILOGUE

# ---- pictures ----

# img_get(path) -> its IC, read and decoded the first time (IC_px 0 when that failed)
img_get:
    PROLOGUE 32
    mov r12, rdi
    lea rbx, [rip + img_cache]
    xor r13d, r13d
1:  cmp r13d, [rip + img_n]
    jae 2f
    mov rdi, [rbx + IC_path]
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jnz .Lig_ret
    add rbx, IC_SIZE
    inc r13d
    jmp 1b
2:  cmp r13d, IC_MAX
    jb 4f
    # full: forget them all
    lea rbx, [rip + img_cache]
    xor r13d, r13d
3:  mov rdi, [rbx + IC_path]
    call mem_free
    mov rdi, [rbx + IC_px]
    call mem_free
    add rbx, IC_SIZE
    inc r13d
    cmp r13d, IC_MAX
    jb 3b
    mov dword ptr [rip + img_n], 0
    lea rbx, [rip + img_cache]
4:  mov rdi, r12
    call strlen
    mov rdi, r12
    mov rsi, rax
    call mem_dup
    mov [rbx + IC_path], rax
    mov qword ptr [rbx + IC_px], 0
    inc dword ptr [rip + img_n]
    mov rdi, r12
    call file_read_all
    test rax, rax
    jz .Lig_ret
    mov r14, rax
    mov r15, rdx
    mov rdi, rax
    mov rsi, rdx
    mov rdx, r12
    call image_sniff
    test eax, eax
    jz .Lig_free
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 0
    mov rdi, r14
    mov rsi, r15
    mov edx, eax
    mov rcx, rsp
    call image_decode
    test eax, eax
    jnz .Lig_free
    mov eax, [rsp + IMG_w]
    mov [rbx + IC_nw], eax
    mov ecx, [rsp + IMG_h]
    mov [rbx + IC_nh], ecx
    test eax, eax
    jz .Lig_drop
    test ecx, ecx
    jz .Lig_drop
    mov edi, 900
    call sc
    cmp [rsp + IMG_w], eax
    jg 5f
    mov rax, [rsp + IMG_px]     # small enough as it is
    mov [rbx + IC_px], rax
    mov eax, [rsp + IMG_w]
    mov [rbx + IC_sw], eax
    mov eax, [rsp + IMG_h]
    mov [rbx + IC_sh], eax
    jmp .Lig_free
5:  mov [rbx + IC_sw], eax
    mov ecx, eax
    mov eax, [rsp + IMG_h]
    imul eax, ecx
    cdq
    idiv dword ptr [rsp + IMG_w]
    cmp eax, 1
    jge 6f
    mov eax, 1
6:  mov [rbx + IC_sh], eax
    imul eax, [rbx + IC_sw]
    shl eax, 2
    mov edi, eax
    call mem_alloc_try
    test rax, rax
    jz .Lig_drop
    mov [rbx + IC_px], rax
    mov rdi, rbx
    mov rsi, rsp
    call img_shrink
.Lig_drop:
    mov rdi, rsp
    call image_free
.Lig_free:
    mov rdi, r14
    call mem_free
.Lig_ret:
    mov rax, rbx
    EPILOGUE

# img_shrink(IC, IMG*): the picture into IC_px, each pixel the average of the ones it stands for
img_shrink:
    PROLOGUE 64
    mov rbx, rdi
    mov rax, [rbx + IC_px]
    mov [rsp + 24], rax
    mov rax, [rsi + IMG_px]
    mov [rsp + 32], rax
    mov dword ptr [rsp], 0
.Lis_y:
    mov eax, [rsp]
    cmp eax, [rbx + IC_sh]
    jae .Lis_ret
    imul eax, [rbx + IC_nh]
    xor edx, edx
    div dword ptr [rbx + IC_sh]
    mov [rsp + 8], eax
    mov eax, [rsp]
    inc eax
    imul eax, [rbx + IC_nh]
    xor edx, edx
    div dword ptr [rbx + IC_sh]
    mov ecx, [rsp + 8]
    inc ecx
    cmp eax, ecx
    jae 1f
    mov eax, ecx
1:  cmp eax, [rbx + IC_nh]
    jbe 2f
    mov eax, [rbx + IC_nh]
2:  mov [rsp + 12], eax
    mov dword ptr [rsp + 4], 0
.Lis_x:
    mov eax, [rsp + 4]
    cmp eax, [rbx + IC_sw]
    jae .Lis_ynext
    imul eax, [rbx + IC_nw]
    xor edx, edx
    div dword ptr [rbx + IC_sw]
    mov [rsp + 16], eax
    mov eax, [rsp + 4]
    inc eax
    imul eax, [rbx + IC_nw]
    xor edx, edx
    div dword ptr [rbx + IC_sw]
    mov ecx, [rsp + 16]
    inc ecx
    cmp eax, ecx
    jae 3f
    mov eax, ecx
3:  cmp eax, [rbx + IC_nw]
    jbe 4f
    mov eax, [rbx + IC_nw]
4:  mov [rsp + 20], eax
    xor r8d, r8d
    xor r9d, r9d
    xor r10d, r10d
    xor r11d, r11d
    xor r15d, r15d
    mov r13d, [rsp + 8]
.Lis_sy:
    cmp r13d, [rsp + 12]
    jae .Lis_avg
    mov eax, r13d
    imul eax, [rbx + IC_nw]
    add eax, [rsp + 16]
    mov rsi, [rsp + 32]
    lea rsi, [rsi + rax*4]
    mov r14d, [rsp + 16]
.Lis_sx:
    cmp r14d, [rsp + 20]
    jae .Lis_synext
    mov eax, [rsi]
    add rsi, 4
    mov ecx, eax
    and ecx, 255
    add r8d, ecx
    shr eax, 8
    mov ecx, eax
    and ecx, 255
    add r9d, ecx
    shr eax, 8
    mov ecx, eax
    and ecx, 255
    add r10d, ecx
    shr eax, 8
    add r11d, eax
    inc r15d
    inc r14d
    jmp .Lis_sx
.Lis_synext:
    inc r13d
    jmp .Lis_sy
.Lis_avg:
    mov eax, r11d
    xor edx, edx
    div r15d
    mov ecx, eax
    shl ecx, 8
    mov eax, r10d
    xor edx, edx
    div r15d
    or ecx, eax
    shl ecx, 8
    mov eax, r9d
    xor edx, edx
    div r15d
    or ecx, eax
    shl ecx, 8
    mov eax, r8d
    xor edx, edx
    div r15d
    or ecx, eax
    mov rdi, [rsp + 24]
    mov [rdi], ecx
    add qword ptr [rsp + 24], 4
    inc dword ptr [rsp + 4]
    jmp .Lis_x
.Lis_ynext:
    inc dword ptr [rsp]
    jmp .Lis_y
.Lis_ret:
    EPILOGUE

# px_over(dst, src) -> eax: src, premultiplied, over dst
px_over:
    mov r8d, esi
    shr r8d, 24
    mov r10d, 255
    sub r10d, r8d               # how much shows through
    xor eax, eax
    xor ecx, ecx
1:  mov edx, edi
    shr edx, cl
    and edx, 255
    imul edx, r10d
    add edx, 128
    imul edx, edx, 257
    shr edx, 16
    mov r11d, esi
    shr r11d, cl
    and r11d, 255
    add edx, r11d
    cmp edx, 255
    jbe 2f
    mov edx, 255
2:  shl edx, cl
    or eax, edx
    add ecx, 8
    cmp ecx, 24
    jb 1b
    or eax, 0xff000000
    ret

# img_blit(IC, x, y, w, h): the picture at that size, inside the clip
img_blit:
    PROLOGUE 64
    mov rbx, rdi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov eax, esi
    cmp eax, [rip + g_cv + CV_cx0]
    jge 1f
    mov eax, [rip + g_cv + CV_cx0]
1:  mov [rsp + 16], eax
    mov eax, esi
    add eax, ecx
    cmp eax, [rip + g_cv + CV_cx1]
    jle 2f
    mov eax, [rip + g_cv + CV_cx1]
2:  mov [rsp + 20], eax
    cmp eax, [rsp + 16]
    jle .Lib_ret
    mov eax, edx
    cmp eax, [rip + g_cv + CV_cy0]
    jge 3f
    mov eax, [rip + g_cv + CV_cy0]
3:  mov [rsp + 24], eax
    mov eax, edx
    add eax, r8d
    cmp eax, [rip + g_cv + CV_cy1]
    jle 4f
    mov eax, [rip + g_cv + CV_cy1]
4:  mov [rsp + 28], eax
    cmp eax, [rsp + 24]
    jle .Lib_ret
    # picture pixels per screen pixel, 16.16
    mov eax, [rbx + IC_sw]
    shl rax, 16
    xor edx, edx
    mov ecx, [rsp + 8]
    div rcx
    mov [rsp + 32], eax
    mov eax, [rbx + IC_sh]
    shl rax, 16
    xor edx, edx
    mov ecx, [rsp + 12]
    div rcx
    mov [rsp + 36], eax
    mov r12d, [rsp + 24]
.Lib_y:
    cmp r12d, [rsp + 28]
    jge .Lib_ret
    mov eax, r12d
    sub eax, [rsp + 4]
    mov ecx, [rsp + 36]
    imul rax, rcx
    shr rax, 16
    cmp eax, [rbx + IC_sh]
    jb 5f
    mov eax, [rbx + IC_sh]
    dec eax
5:  imul eax, [rbx + IC_sw]
    mov r14, [rbx + IC_px]
    lea r14, [r14 + rax*4]
    mov eax, r12d
    imul eax, [rip + g_cv + CV_stride]
    add eax, [rsp + 16]
    mov r15, [rip + g_cv + CV_pixels]
    lea r15, [r15 + rax*4]
    mov eax, [rsp + 16]
    sub eax, [rsp]
    mov ecx, [rsp + 32]
    imul rax, rcx
    mov r13, rax
    mov r9d, [rsp + 16]
.Lib_x:
    cmp r9d, [rsp + 20]
    jge .Lib_ynext
    mov rax, r13
    shr rax, 16
    cmp eax, [rbx + IC_sw]
    jb 6f
    mov eax, [rbx + IC_sw]
    dec eax
6:  mov eax, [r14 + rax*4]
    mov ecx, eax
    shr ecx, 24
    cmp ecx, 255
    je 7f
    test ecx, ecx
    jz 8f
    mov edi, [r15]
    mov esi, eax
    call px_over
7:  mov [r15], eax
8:  add r15, 4
    mov ecx, [rsp + 32]
    add r13, rcx
    inc r9d
    jmp .Lib_x
.Lib_ynext:
    inc r12d
    jmp .Lib_y
.Lib_ret:
    EPILOGUE

# img_place(src, len, width or 0) -> 1 when the picture a file names was put on the page: on a line
#   of its own, at its own size or the width asked, no wider than the block
img_place:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    test r13, r13
    jz .Lip_no
    lea rsi, [rdi + rsi]
    call is_url                 # pictures from the web are not fetched
    test eax, eax
    jnz .Lip_no
    mov rdi, r12
    mov rsi, r13
    call md_path
    test rax, rax
    jz .Lip_no
    mov rdi, rax
    call img_get
    mov rbx, rax
    cmp qword ptr [rbx + IC_px], 0
    je .Lip_no
    call word_flush
    cmp dword ptr [rip + fl_any], 0
    je 1f
    call flow_break
1:  mov edi, [rbx + IC_nw]
    test r14d, r14d
    jz 2f
    mov edi, r14d
2:  call sc
    mov r14d, eax
    mov eax, [rip + fl_x1]
    sub eax, [rip + fl_x0]
    cmp r14d, eax
    jle 3f
    mov r14d, eax
3:  cmp r14d, 1
    jge 4f
    mov r14d, 1
4:  mov eax, [rbx + IC_nh]
    imul eax, r14d
    cdq
    idiv dword ptr [rbx + IC_nw]
    cmp eax, 1
    jge 5f
    mov eax, 1
5:  mov r15d, eax
    cmp dword ptr [rip + md_nodraw], 0
    jne 6f
    mov rdi, rbx
    mov esi, [rip + fl_x]
    mov edx, [rip + md_y]
    mov ecx, r14d
    mov r8d, r15d
    call img_blit
6:  add [rip + fl_x], r14d
    mov eax, [rip + fl_x]
    cmp eax, [rip + fl_maxx]
    jle 7f
    mov [rip + fl_maxx], eax
7:  mov eax, r15d
    sub eax, [rip + fl_lh]
    add eax, [rip + g_mt + 4*MI_4]
    add [rip + md_y], eax
    call flow_break
    mov eax, 1
    EPILOGUE
.Lip_no:
    xor eax, eax
    EPILOGUE

# html_attr(p, end, name=, its length) -> rax the attribute's value in a tag, rdx its length; rax 0
#   without it
html_attr:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
1:  mov rsi, r13
    sub rsi, r12
    jle .Lha_no
    mov rdi, r12
    mov rdx, r14
    mov rcx, r15
    call str_ifind
    test rax, rax
    js .Lha_no
    lea rbx, [r12 + rax]
    lea r12, [rbx + r15]
    movzx eax, byte ptr [rbx - 1]
    cmp al, ' '
    je 2f
    cmp al, 10
    je 2f
    cmp al, 9
    jne 1b
2:  cmp r12, r13
    jae .Lha_no
    movzx ecx, byte ptr [r12]
    cmp cl, '"'
    je 5f
    cmp cl, 39
    je 5f
    mov rax, r12
3:  cmp r12, r13
    jae 4f
    movzx ecx, byte ptr [r12]
    cmp cl, ' '
    je 4f
    cmp cl, '>'
    je 4f
    inc r12
    jmp 3b
4:  mov rdx, r12
    sub rdx, rax
    EPILOGUE
5:  inc r12
    mov rax, r12
6:  cmp r12, r13
    jae 4b
    cmp byte ptr [r12], cl
    je 4b
    inc r12
    jmp 6b
.Lha_no:
    xor eax, eax
    xor edx, edx
    EPILOGUE

# tag_center(p, end) -> 1 when the text starts with a tag that centers it
tag_center:
    PROLOGUE
    xor eax, eax
    cmp rdi, rsi
    jae 3f
    cmp byte ptr [rdi], '<'
    jne 3f
    mov r12, rdi
1:  cmp rdi, rsi
    jae 2f
    cmp byte ptr [rdi], '>'
    je 2f
    inc rdi
    jmp 1b
2:  mov rsi, rdi
    sub rsi, r12
    mov rdi, r12
    lea rdx, [rip + .Lh_center]
    mov ecx, 6
    call str_ifind
    not rax
    shr rax, 63
3:  EPILOGUE

# flow_center(ptr, len): flow, each line in the middle of the block: once to learn the lines'
#   widths, once to draw them
flow_center:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov eax, [rip + md_y]
    mov [rsp], eax
    mov eax, [rip + md_nodraw]
    mov [rsp + 4], eax
    mov dword ptr [rip + fl_center], 1
    mov dword ptr [rip + md_nodraw], 1
    call flow
    mov eax, [rsp]
    mov [rip + md_y], eax
    mov eax, [rsp + 4]
    mov [rip + md_nodraw], eax
    mov dword ptr [rip + fl_center], 2
    mov rdi, r12
    mov rsi, r13
    call flow
    mov dword ptr [rip + fl_center], 0
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
    mov rdi, r12
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
    mov eax, [rip + md_fence_n]
    lea rdi, [rbx + rax]
    mov rsi, r14
    mov rdx, [rsp]
    call code_begin
    jmp .Lb_next
.Lb_head:
    # <h1> to <h6> on a line
    cmp byte ptr [rbx], '<'
    jne .Lb_hash
    lea rax, [rbx + 4]
    cmp rax, r14
    ja .Lb_hash
    movzx eax, byte ptr [rbx + 1]
    or al, 0x20
    cmp al, 'h'
    jne .Lb_hash
    movzx eax, byte ptr [rbx + 2]
    sub eax, '0'
    cmp eax, 1
    jb .Lb_hash
    cmp eax, 6
    ja .Lb_hash
    movzx ecx, byte ptr [rbx + 3]
    cmp cl, '>'
    je 1f
    cmp cl, ' '
    jne .Lb_hash
1:  mov [rsp + 8], eax
    mov rdi, rbx
    mov rsi, r14
    call tag_center
    mov [rsp + 12], eax
    mov rdi, rbx
2:  cmp byte ptr [rdi], '>'
    je 3f
    inc rdi
    cmp rdi, r14
    jb 2b
    jmp .Lb_hash
3:  inc rdi
    mov [rsp + 16], rdi
    mov rsi, r14
    sub rsi, rdi
    lea rdx, [rip + .Lh_close]
    mov ecx, 3
    call str_ifind
    mov rdx, r14
    test rax, rax
    js 4f
    mov rdx, [rsp + 16]
    add rdx, rax
4:  mov [rsp + 24], rdx
    call para_flush
    mov edi, [rsp + 8]
    mov rsi, [rsp + 16]
    mov rdx, [rsp + 24]
    mov ecx, [rsp + 12]
    call heading
    jmp .Lb_next
.Lb_hash:
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
    xor ecx, ecx
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
    mov rdi, r13
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
    call tag_center
    mov rdi, [rip + pg_start]
    mov rsi, [rip + pg_end]
    sub rsi, rdi
    test eax, eax
    jz 5f
    call flow_center
    jmp .Lpf_done
5:  call flow
.Lpf_done:
    mov eax, [rip + pg_kind]
    mov [rip + md_prev], eax
    mov dword ptr [rip + pg_kind], 0
.Lpf_ret:
    EPILOGUE

# heading(level, p, end, centered)
heading:
    PROLOGUE
    mov ebx, edi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
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
    test r14d, r14d
    jz 61f
    call flow_center
    jmp 62f
61: call flow
62: # the two largest have a line under them
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

# code_grammar(name, len) -> the grammar a code block's language names, or 0: a grammar's name, or
#   the ending of its files
code_grammar:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor eax, eax
    test r13, r13
    jz 9f
    lea rbx, [rip + md_aliases]
1:  mov rdx, [rbx]
    test rdx, rdx
    jz 3f
    mov rdi, r12
    mov rsi, r13
    mov rcx, [rbx + 8]
    call str_ieq
    test eax, eax
    jz 2f
    mov r12, [rbx + 16]
    mov r13, [rbx + 24]
    jmp 3f
2:  add rbx, 32
    jmp 1b
3:  mov rdi, r12
    mov rsi, r13
    call syntax_by_name
    test rax, rax
    jnz 9f
    lea rdi, [rip + cb_name]
    mov word ptr [rdi], 0x2e78  # "x."
    xor ecx, ecx
4:  cmp rcx, r13
    jae 6f
    movzx eax, byte ptr [r12 + rcx]
    cmp al, 'A'
    jb 5f
    cmp al, 'Z'
    ja 5f
    add al, 32
5:  mov [rdi + rcx + 2], al
    inc rcx
    jmp 4b
6:  lea rsi, [rcx + 2]
    call syntax_for_name
    mov rdi, rax
    call syntax_ready
9:  EPILOGUE

# code_begin(info, end, first line): a code block's top: the language its fence names and Copy
code_begin:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov [rip + cb_start], rdx
1:  cmp r12, r13
    jae 2f
    cmp byte ptr [r12], ' '
    jne 2f
    inc r12
    jmp 1b
2:  mov r14, r12
3:  cmp r14, r13
    jae 4f
    movzx eax, byte ptr [r14]
    cmp al, ' '
    je 4f
    cmp al, 9
    je 4f
    cmp al, '{'
    je 4f
    inc r14
    jmp 3b
4:  sub r14, r12
    cmp r14, 24
    jbe 5f
    mov r14d, 24
5:  mov dword ptr [rip + cb_state], 0
    inc dword ptr [rip + cb_idx]
    mov rdi, r12
    mov rsi, r14
    call code_grammar
    mov [rip + cb_gr], rax
    # the label: the language in capitals
    lea rdi, [rip + cb_label]
    test r14, r14
    jnz 6f
    mov dword ptr [rdi], 0x54584554     # TEXT
    mov r14d, 4
    jmp 9f
6:  xor ecx, ecx
7:  cmp rcx, r14
    jae 9f
    movzx eax, byte ptr [r12 + rcx]
    cmp al, 'a'
    jb 8f
    cmp al, 'z'
    ja 8f
    sub al, 32
8:  mov [rdi + rcx], al
    inc rcx
    jmp 7b
9:  mov [rsp], r14d
    mov edi, BK_CODE
    call block_gap
    mov eax, [rip + md_y]
    mov [rip + cb_y0], eax
    M ebx, MI_24
    mov edi, [rip + md_cx0]
    mov esi, eax
    mov edx, [rip + md_cw]
    mov ecx, ebx
    mov r8d, [rip + md_codebg]
    call gfx_fill
    lea rdi, [rip + g_face_mini]
    mov esi, [rip + md_cx0]
    add esi, [rip + g_mt + 4*MI_12]
    mov edx, [rip + md_y]
    mov ecx, ebx
    lea r8, [rip + cb_label]
    mov r9d, [rsp]
    COLOR eax, T_MUTED
    push rax
    push rax
    call ui_text_v
    add rsp, 16
    # Copy, at the right
    lea rdi, [rip + g_face_mini]
    lea rsi, [rip + .Ls_copied]
    mov edx, 6
    call text_width
    M ecx, MI_8
    lea r13d, [rax + rcx*2]
    mov r12d, [rip + md_cx0]
    add r12d, [rip + md_cw]
    sub r12d, r13d
    sub r12d, [rip + g_mt + 4*MI_4]
    mov edi, [rip + cb_idx]
    add edi, ID_MD_COPY
    mov esi, r12d
    mov edx, [rip + md_y]
    mov ecx, r13d
    mov r8d, ebx
    call ui_btn
    mov r14d, eax
    test eax, UB_PRESS
    jz 10f
    mov eax, [rip + cb_idx]
    mov [rip + cb_copy], eax
    mov [rip + md_copied], eax
    mov dword ptr [rip + md_btn_hit], 1
10: # it says Copied until the pointer leaves it
    lea r15, [rip + .Ls_copy]
    mov eax, [rip + cb_idx]
    cmp eax, [rip + md_copied]
    jne 12f
    test r14d, UB_HOVER
    jnz 11f
    mov dword ptr [rip + md_copied], 0
    jmp 12f
11: lea r15, [rip + .Ls_copied]
12: COLOR eax, T_MUTED
    test r14d, UB_HOVER
    jz 13f
    COLOR eax, T_FG
    mov dword ptr [rip + g_cursor], CUR_POINTER
13: lea rdi, [rip + g_face_mini]
    mov esi, r12d
    mov edx, [rip + md_y]
    mov ecx, r13d
    mov r8d, ebx
    mov r9, r15
    push rax
    push rax
    call ui_text_center
    add rsp, 16
    add [rip + md_y], ebx
    mov edi, [rip + md_cx0]
    mov esi, [rip + md_y]
    mov edx, [rip + md_cw]
    mov ecx, [rip + g_border]
    COLOR r8d, T_BORDER
    call gfx_fill
    mov eax, [rip + g_border]
    add [rip + md_y], eax
    call code_pad
    EPILOGUE

# code_end(end of its text): the block's frame; its text to the clipboard when Copy was pressed
code_end:
    PROLOGUE
    mov r12, rdi
    call code_pad
    mov ebx, [rip + g_border]
    mov edi, [rip + md_cx0]
    mov esi, [rip + cb_y0]
    mov edx, [rip + md_cw]
    mov ecx, ebx
    COLOR r8d, T_BORDER
    call gfx_fill
    mov edi, [rip + md_cx0]
    mov esi, [rip + md_y]
    sub esi, ebx
    mov edx, [rip + md_cw]
    mov ecx, ebx
    COLOR r8d, T_BORDER
    call gfx_fill
    mov edi, [rip + md_cx0]
    mov esi, [rip + cb_y0]
    mov edx, ebx
    mov ecx, [rip + md_y]
    sub ecx, esi
    COLOR r8d, T_BORDER
    call gfx_fill
    mov edi, [rip + md_cx0]
    add edi, [rip + md_cw]
    sub edi, ebx
    mov esi, [rip + cb_y0]
    mov edx, ebx
    mov ecx, [rip + md_y]
    sub ecx, esi
    COLOR r8d, T_BORDER
    call gfx_fill
    mov eax, [rip + cb_copy]
    test eax, eax
    jz 2f
    cmp eax, [rip + cb_idx]
    jne 2f
    mov dword ptr [rip + cb_copy], 0
    mov rdi, [rip + cb_start]
    mov rsi, r12
    sub rsi, rdi
    jle 2f
    cmp byte ptr [rdi + rsi - 1], 10
    jne 1f
    dec rsi
1:  xor edx, edx
    call ed_clip_set
2:  mov dword ptr [rip + md_prev], BK_CODE
    EPILOGUE

# code_line(p, end): a line of a code block, in its language's colors; one wider than the column
#   goes on below
code_line:
    PROLOGUE 32
    mov r12, rdi
    mov r13, rsi
    sub r13, r12
    mov qword ptr [rsp + 8], 0  # its bytes' classes, or 0
    mov rdi, [rip + cb_gr]
    test rdi, rdi
    jz 1f
    cmp r13, CLS_MAX
    ja 1f
    mov rsi, r12
    mov rdx, r13
    mov ecx, [rip + cb_state]
    lea r8, [rip + cb_cls]
    call tokenize
    mov [rip + cb_state], eax
    lea rax, [rip + cb_cls]
    mov [rsp + 8], rax
1:  M eax, MI_12
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
    jle 2f
    lea rdi, [rip + g_face_code]
    mov rsi, r12
    mov rdx, r13
    mov ecx, r14d
    call text_fit
    mov rbx, rax
    test rbx, rbx
    jnz 2f
    mov rdi, r12
    mov rsi, r13
    call utf8_decode
    mov ebx, edx
2:  cmp dword ptr [rip + md_collect], 0
    jne 3f
    mov eax, [rip + md_y]
    cmp eax, [rip + md_cy1]
    jge .Lcl_next
    add eax, [rip + g_lh]
    cmp eax, [rip + md_cy0]
    jle .Lcl_next
3:  mov edi, [rip + md_cx0]
    mov esi, [rip + md_y]
    mov edx, [rip + md_cw]
    mov ecx, [rip + g_lh]
    mov r8d, [rip + md_codebg]
    call gfx_fill
    mov dword ptr [rip + sel_soft], 0
    mov rdi, r12
    mov rsi, rbx
    mov edx, [rip + md_cx0]
    add edx, [rsp]
    lea rcx, [rip + g_face_code]
    xor r8d, r8d
    mov r9d, [rip + g_lh]
    call sel_piece
    mov r15d, [rip + md_cx0]
    add r15d, [rsp]
    cmp qword ptr [rsp + 8], 0
    jne 4f
    lea rdi, [rip + g_face_code]
    mov esi, r15d
    mov edx, [rip + md_y]
    add edx, [rip + g_base]
    mov rcx, r12
    mov r8, rbx
    COLOR r9d, T_FG
    call text_draw
    jmp .Lcl_next
4:  mov qword ptr [rsp + 16], 0
5:  mov rcx, [rsp + 16]
    cmp rcx, rbx
    jae .Lcl_next
    mov rsi, [rsp + 8]
    movzx eax, byte ptr [rsi + rcx]
    lea rdx, [rcx + 1]
6:  cmp rdx, rbx
    jae 7f
    movzx edi, byte ptr [rsi + rdx]
    cmp edi, eax
    jne 7f
    inc rdx
    jmp 6b
7:  mov [rsp + 16], rdx
    mov r8, rdx
    sub r8, rcx
    lea rcx, [r12 + rcx]
    lea rdx, [rip + g_theme]
    mov r9d, [rdx + rax*4 + 4*T_SYN]
    lea rdi, [rip + g_face_code]
    mov esi, r15d
    mov edx, [rip + md_y]
    add edx, [rip + g_base]
    call text_draw
    mov r15d, eax
    jmp 5b
.Lcl_next:
    mov eax, [rip + g_lh]
    add [rip + md_y], eax
    cmp qword ptr [rsp + 8], 0
    je 8f
    add [rsp + 8], rbx
8:  add r12, rbx
    sub r13, rbx
    test r13, r13
    jg .Lcl_row
    EPILOGUE

# sel_piece(ptr, len, x, face, gap, line height): the part of a piece of text on the current line
#   that is selected: its background, and its text when the selection is being gathered. gap is
#   the blank before the piece
sel_piece:
    cmp dword ptr [rip + sel_pass], 0
    jne 1f
    ret
1:  PROLOGUE 48
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    mov rbx, rcx
    mov [rsp], r8d
    mov [rsp + 4], r9d
    test r13, r13
    jz .Lsp_ret
    mov eax, [rip + md_y]
    lea ecx, [rax + r9]
    cmp ecx, [rip + ss_y]
    jle .Lsp_ret
    cmp eax, [rip + se_y]
    jg .Lsp_ret
    # from its first byte, or on the selection's first line from where that starts
    xor r15d, r15d
    cmp eax, [rip + ss_y]
    jg 2f
    mov ecx, [rip + ss_x]
    sub ecx, r14d
    jle 2f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call text_fit
    mov r15, rax
2:  mov [rsp + 8], r15
    # to its last, or on the selection's last line to where that ends
    mov r15, r13
    mov eax, [rip + md_y]
    add eax, [rsp + 4]
    cmp [rip + se_y], eax
    jge 4f
    xor r15d, r15d
    mov ecx, [rip + se_x]
    sub ecx, r14d
    jle 4f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call text_fit
    mov r15, rax
4:  cmp r15, [rsp + 8]
    jbe .Lsp_ret
    mov [rsp + 16], r15
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [rsp + 8]
    call text_width
    add eax, r14d
    mov [rsp + 24], eax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [rsp + 16]
    call text_width
    add eax, r14d
    mov [rsp + 28], eax
    # the blank before it too, when the selection came across it
    cmp qword ptr [rsp + 8], 0
    jne 6f
    mov eax, [rsp]
    test eax, eax
    jz 6f
    mov ecx, [rip + md_y]
    cmp ecx, [rip + ss_y]
    jg 5f
    mov ecx, r14d
    sub ecx, eax
    cmp [rip + ss_x], ecx
    jg 6f
5:  sub [rsp + 24], eax
6:  mov edi, [rsp + 24]
    mov esi, [rip + md_y]
    mov edx, [rsp + 28]
    sub edx, edi
    mov ecx, [rsp + 4]
    COLOR r8d, T_SELECTION
    call gfx_fill
    cmp dword ptr [rip + md_collect], 0
    je .Lsp_ret
    # gathered: a new block on a new line, wrapped text and words a blank apart
    lea rdi, [rip + md_copy_sb]
    cmp qword ptr [rdi + SB_len], 0
    je 9f
    mov eax, [rip + md_y]
    cmp eax, [rip + sel_lasty]
    je 7f
    mov esi, ' '
    cmp dword ptr [rip + sel_soft], 0
    jne 8f
    mov esi, 10
    jmp 8f
7:  cmp dword ptr [rsp], 0
    je 9f
    mov esi, ' '
8:  call sb_push_byte
9:  lea rdi, [rip + md_copy_sb]
    mov rsi, r12
    add rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    sub rdx, [rsp + 8]
    call sb_push
    mov eax, [rip + md_y]
    mov [rip + sel_lasty], eax
.Lsp_ret:
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
    mov dword ptr [rip + fl_any], 0
    mov dword ptr [rip + fl_space], 0
    mov dword ptr [rip + fl_lastst], 0
    mov dword ptr [rip + sel_soft], 1
    cmp dword ptr [rip + fl_center], 1
    jne 1f
    call fl_note
1:  inc dword ptr [rip + fl_line]
# fl_start(): the pen at the start of line fl_line; in the middle less half its width when centered
fl_start:
    mov eax, [rip + fl_x0]
    cmp dword ptr [rip + fl_center], 2
    jne 2f
    mov ecx, [rip + fl_line]
    cmp ecx, LW_MAX
    jae 2f
    lea rdx, [rip + fl_lw]
    mov edx, [rdx + rcx*4]
    mov ecx, [rip + fl_x1]
    sub ecx, eax
    sub ecx, edx
    jle 2f
    shr ecx, 1
    add eax, ecx
2:  mov [rip + fl_x], eax
    ret

# fl_note(): the width of the line that ends here
fl_note:
    mov ecx, [rip + fl_line]
    cmp ecx, LW_MAX
    jae 1f
    mov eax, [rip + fl_x]
    sub eax, [rip + fl_x0]
    lea rdx, [rip + fl_lw]
    mov [rdx + rcx*4], eax
1:  ret

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
    cmp dword ptr [rip + md_collect], 0
    jne .Ltk_on
    mov eax, [rip + md_y]
    cmp eax, [rip + md_cy1]
    jge .Ltk_ret
    add eax, [rip + fl_lh]
    cmp eax, [rip + md_cy0]
    jle .Ltk_ret
.Ltk_on:
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
1:  mov rdi, r12
    mov rsi, r13
    mov edx, r14d
    add edx, [rip + fl_lead]
    mov rcx, rbx
    mov r8d, [rip + fl_gap]
    mov r9d, [rip + fl_lh]
    call sel_piece
    test dword ptr [rip + fl_tst], ST_LINK
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
    cmp dword ptr [rip + fl_twice], 0
    je 4f
    # without a bold face: the text again, a little to the right
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
    mov edi, r14d
    mov rsi, r12
    mov rdx, r13
    call pick_face
    mov rbx, rax
    xor r15d, r15d              # room beside code
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
    mov dword ptr [rip + fl_gap], 0
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
    mov edx, [rsp + 4]
    mov [rip + fl_gap], edx
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
    mov dword ptr [rip + sel_soft], 0
    mov qword ptr [rip + fl_linkend], 0
    mov qword ptr [rip + fl_codeend], 0
    mov dword ptr [rip + fl_line], 0
    call fl_start
    mov eax, [rip + fl_x0]
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
    cmp qword ptr [rip + fl_linkend], 0
    jne 4f
    # a picture file is drawn; one that is not there, or on the web, is its words
    mov rdi, [rip + lp_url]
    mov rsi, [rip + lp_urllen]
    xor edx, edx
    call img_place
    test eax, eax
    jz 4f
    mov r12, [rip + lp_after]
    jmp .Lf_loop
4:  inc r12
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
    cmp eax, -2
    jne 41f
    # <img src= width=>
    lea rdi, [r12 + 1]
    mov rsi, r15
    lea rdx, [rip + .Lh_src]
    mov ecx, 4
    call html_attr
    test rax, rax
    jz 7f
    mov [rsp + 16], rax
    mov [rsp + 24], rdx
    lea rdi, [r12 + 1]
    mov rsi, r15
    lea rdx, [rip + .Lh_width]
    mov ecx, 6
    call html_attr
    xor ecx, ecx
    test rax, rax
    jz 40f
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    mov ecx, eax
40: mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    mov edx, ecx
    call img_place
    jmp 7f
41: cmp eax, -1
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
    cmp dword ptr [rip + fl_center], 1
    jne 2f
    call fl_note
2:  cmp dword ptr [rip + fl_any], 0
    je 1f
    mov eax, [rip + fl_lh]
    add [rip + md_y], eax
1:  mov eax, [rip + fl_maxx]
    sub eax, [rip + fl_x0]
    EPILOGUE

.section .rodata
.Ls_markdown: .asciz "Markdown"
.Ls_preview: .asciz "Rendered"
.Ls_edit: .asciz "Raw"
.Ls_state: .asciz " preview=1"
.Ls_copy: .asciz "Copy"
.Ls_copied: .asciz "Copied"
.La_bash: .ascii "bash"
.La_zsh: .ascii "zsh"
.La_console: .ascii "console"
.La_shell: .ascii "shell"
.La_sh: .ascii "sh"
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
.Lt_img: .ascii "img"
.Lh_src: .ascii "src="
.Lh_width: .ascii "width="
.Lh_center: .ascii "center"
.Lh_close: .ascii "</h"
.p2align 3
# a code block's language, the one it is colored as
md_aliases:
    .quad .La_bash, 4, .La_sh, 2, .La_zsh, 3, .La_sh, 2, .La_console, 7, .La_sh, 2
    .quad .La_shell, 5, .La_sh, 2, 0, 0, 0, 0
md_schemes:
    .quad .Lu_http, 7, .Lu_https, 8, .Lu_mailto, 7, 0, 0
# name, length, the character it stands for
md_entities:
    .quad .Le_amp, 5, '&', .Le_lt, 4, '<', .Le_gt, 4, '>', .Le_quot, 6, '"'
    .quad .Le_apos, 5, 39, .Le_nbsp, 6, ' ', 0, 0, 0
# name, length, style (-1: a line break, -2: a picture)
md_tags:
    .quad .Lt_b, 1, ST_BOLD, .Lt_strong, 6, ST_BOLD, .Lt_i, 1, ST_ITALIC, .Lt_em, 2, ST_ITALIC
    .quad .Lt_br, 2, -1, .Lt_img, 3, -2, 0, 0, 0
