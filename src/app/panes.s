# panes: the views of the title bar's active tab, side by side and stacked, with dividers to drag;
# a file dragged from the explorer onto a pane's edge splits it
.include "raftaar.inc"

.equ PN_MAX, 64
.equ PN_LEAF, 1
.equ PN_ROW, 2                  # a left of b
.equ PN_COL, 3                  # a above b
STRUCT
F PN_kind, 4            # 0 free
F PN_parent, 4          # -1: the root of its group
F PN_a, 4
F PN_b, 4
F PN_ratio, 4           # a's share of the room, of 65536
F PN_group, 4
F PN_view, 8            # a leaf: TAB_id
F PN_x, 4               # where the last frame laid it out
F PN_y, 4
F PN_w, 4
F PN_h, 4
F PN_bits, 4           # a split: UB_* of its divider in this frame
F PN_pad, 4
ENDSTRUCT PN_SIZE
.equ ID_PANE_DIV, 0x2b00         # + node
.equ DRAG_MAX, 4096

.bss
.p2align 3
nodes: .zero PN_MAX * PN_SIZE
.globl g_split_next, g_drag_on
g_split_next: .long 0           # SPLIT_*: the next tab added is a pane beside the active one
g_drag_on: .long 0              # a file is being dragged from the explorer
div_grab: .long 0               # a divider's drag: the pointer's distance from it at the press
div_px: .long 0                 # where that press was, and whether the pointer has moved since
div_py: .long 0
div_moved: .long 0
solo: .zero 16                  # the rect of a tab with one view
cur_group: .long 0
drag_path: .zero DRAG_MAX
drop_rect: .zero 16             # the half of a pane a drop would take
drop_view: .quad 0              # that pane's view (TAB_id), 0 none
drop_dir: .long 0               # SPLIT_*, 0 the whole pane: an ordinary tab
ord_mid: .zero 8                # Next Pane: the middle of the tab, doubled x and y

.text

# pn_ptr(i) -> rax
pn_ptr:
    mov eax, edi
    imul rax, rax, PN_SIZE
    lea rcx, [rip + nodes]
    add rax, rcx
    ret

# pn_alloc() -> eax node, zeroed, or -1
pn_alloc:
    lea rcx, [rip + nodes]
    xor eax, eax
1:  cmp dword ptr [rcx + PN_kind], 0
    je 2f
    add rcx, PN_SIZE
    inc eax
    cmp eax, PN_MAX
    jb 1b
    mov eax, -1
    ret
2:  pxor xmm0, xmm0
    movdqu [rcx], xmm0
    movdqu [rcx + 16], xmm0
    movdqu [rcx + 32], xmm0
    mov qword ptr [rcx + 48], 0
    ret

# pn_free_count() -> eax
pn_free_count:
    lea rcx, [rip + nodes]
    xor eax, eax
    mov edx, PN_MAX
1:  cmp dword ptr [rcx + PN_kind], 0
    jne 2f
    inc eax
2:  add rcx, PN_SIZE
    dec edx
    jnz 1b
    ret

# pn_leaf(view id) -> eax node or -1
pn_leaf:
    lea rcx, [rip + nodes]
    xor eax, eax
1:  cmp dword ptr [rcx + PN_kind], PN_LEAF
    jne 2f
    cmp [rcx + PN_view], rdi
    je 9f
2:  add rcx, PN_SIZE
    inc eax
    cmp eax, PN_MAX
    jb 1b
    mov eax, -1
9:  ret

# pn_root(group) -> eax node or -1
pn_root:
    lea rcx, [rip + nodes]
    xor eax, eax
1:  cmp dword ptr [rcx + PN_kind], 0
    je 2f
    cmp dword ptr [rcx + PN_parent], -1
    jne 2f
    cmp [rcx + PN_group], edi
    je 9f
2:  add rcx, PN_SIZE
    inc eax
    cmp eax, PN_MAX
    jb 1b
    mov eax, -1
9:  ret

# panes_any() -> eax 1 when some tab has more than one pane
FN panes_any
    call pn_free_count
    cmp eax, PN_MAX
    setne al
    movzx eax, al
    ret

# pane_split(target view id, new view id, SPLIT_*, group) -> eax 1 when the new view is a pane beside
#   the target, 0 when there is no room for more panes
FN pane_split
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    mov r15d, ecx
    call pn_free_count
    cmp eax, 3
    jb .Lps_no
    mov rdi, r12
    call pn_leaf
    mov ebx, eax                # the target's leaf
    cmp ebx, -1
    jne 1f
    call pn_alloc               # a tab with one view had no nodes
    mov ebx, eax
    mov edi, eax
    call pn_ptr
    mov dword ptr [rax + PN_kind], PN_LEAF
    mov dword ptr [rax + PN_parent], -1
    mov [rax + PN_group], r15d
    mov [rax + PN_view], r12
1:  call pn_alloc
    mov [rsp], eax              # the new leaf
    mov edi, eax
    call pn_ptr
    mov dword ptr [rax + PN_kind], PN_LEAF
    mov [rax + PN_group], r15d
    mov [rax + PN_view], r13
    call pn_alloc
    mov [rsp + 4], eax          # the split
    mov edi, eax
    call pn_ptr
    mov r13, rax
    mov edx, PN_ROW
    cmp r14d, SPLIT_RIGHT
    je 2f
    cmp r14d, SPLIT_LEFT
    je 2f
    mov edx, PN_COL
2:  mov [r13 + PN_kind], edx
    mov dword ptr [r13 + PN_ratio], 32768
    mov [r13 + PN_group], r15d
    mov edi, ebx
    call pn_ptr
    mov r12, rax                # the target
    mov ecx, [r12 + PN_parent]
    mov [r13 + PN_parent], ecx
    mov eax, [rsp]
    mov [r13 + PN_a], ebx
    mov [r13 + PN_b], eax
    cmp r14d, SPLIT_LEFT
    jb 3f
    mov [r13 + PN_a], eax       # the new one first: left or above
    mov [r13 + PN_b], ebx
3:  cmp ecx, -1
    je 5f
    mov edi, ecx
    call pn_ptr
    mov ecx, [rsp + 4]
    cmp [rax + PN_a], ebx
    jne 4f
    mov [rax + PN_a], ecx
    jmp 5f
4:  mov [rax + PN_b], ecx
5:  mov ecx, [rsp + 4]
    mov [r12 + PN_parent], ecx
    mov edi, [rsp]
    call pn_ptr
    mov ecx, [rsp + 4]
    mov [rax + PN_parent], ecx
    mov eax, 1
    EPILOGUE
.Lps_no:
    xor eax, eax
    EPILOGUE

# pane_remove(view id) -> rax the view of its tab that takes its room (0: it had the tab alone)
FN pane_remove
    PROLOGUE
    call pn_leaf
    cmp eax, -1
    je .Lpr_none
    mov ebx, eax
    mov edi, eax
    call pn_ptr
    mov r12, rax                # the leaf
    mov r13d, [r12 + PN_parent]
    mov dword ptr [r12 + PN_kind], 0
    cmp r13d, -1
    je .Lpr_none
    mov edi, r13d
    call pn_ptr
    mov r14, rax                # its split
    mov r15d, [r14 + PN_a]
    cmp r15d, ebx
    jne 1f
    mov r15d, [r14 + PN_b]      # the sibling
1:  mov ebx, [r14 + PN_parent]
    mov dword ptr [r14 + PN_kind], 0
    mov edi, r15d
    call pn_ptr
    mov r12, rax
    mov [r12 + PN_parent], ebx
    cmp ebx, -1
    je 3f
    mov edi, ebx
    call pn_ptr
    cmp [rax + PN_a], r13d
    jne 2f
    mov [rax + PN_a], r15d
    jmp 4f
2:  mov [rax + PN_b], r15d
    jmp 4f
3:  # the sibling is the root now: a view alone needs no nodes
    cmp dword ptr [r12 + PN_kind], PN_LEAF
    jne 4f
    mov dword ptr [r12 + PN_kind], 0
    mov rax, [r12 + PN_view]
    EPILOGUE
4:  # the first leaf of what took the room
    cmp dword ptr [r12 + PN_kind], PN_LEAF
    je 5f
    mov edi, [r12 + PN_a]
    call pn_ptr
    mov r12, rax
    jmp 4b
5:  mov rax, [r12 + PN_view]
    EPILOGUE
.Lpr_none:
    xor eax, eax
    EPILOGUE

# panes_reset(): no tab is split (every tab closed at once)
FN panes_reset
    lea rdi, [rip + nodes]
    mov ecx, PN_MAX * PN_SIZE / 8
    xor eax, eax
    rep stosq
    ret

# ---------------- commands ----------------

# a new terminal beside the active pane, whatever it shows
FN cmd_split_right
    mov dword ptr [rip + g_split_next], SPLIT_RIGHT
    jmp 1f
FN cmd_split_down
    mov dword ptr [rip + g_split_next], SPLIT_DOWN
    jmp 1f
FN cmd_split_left
    mov dword ptr [rip + g_split_next], SPLIT_LEFT
    jmp 1f
FN cmd_split_up
    mov dword ptr [rip + g_split_next], SPLIT_UP
1:  push rax
    call cmd_new_terminal
    mov dword ptr [rip + g_split_next], 0
    pop rax
    ret

# the next pane of the active tab, clockwise around its middle; a tab with one view stays as it is
FN cmd_next_pane
    PROLOGUE 96                 # [rsp] the pane with the keys, +24 one looked at, +48 the next after
                                #   it, +72 the first of all (each an order key: pn_key)
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 9f
    call tab_at
    mov r12, [rax + TAB_group]
    mov r13, [rax + TAB_id]
    mov edi, r12d
    call pn_root
    cmp eax, -1
    je 9f
    mov edi, eax
    call pn_ptr
    mov ecx, [rax + PN_x]       # the tab's middle, doubled
    add ecx, ecx
    add ecx, [rax + PN_w]
    mov [rip + ord_mid], ecx
    mov ecx, [rax + PN_y]
    add ecx, ecx
    add ecx, [rax + PN_h]
    mov [rip + ord_mid + 4], ecx
    mov rdi, r13
    call pn_leaf
    cmp eax, -1
    je 9f
    mov edi, eax
    lea rsi, [rsp]
    call pn_key
    xor r14d, r14d              # a next one found
    xor r15d, r15d              # a first one found
    xor ebx, ebx
1:  mov edi, ebx
    call pn_ptr
    cmp dword ptr [rax + PN_kind], PN_LEAF
    jne 4f
    cmp [rax + PN_group], r12d
    jne 4f
    mov edi, ebx
    lea rsi, [rsp + 24]
    call pn_key
    test r15d, r15d
    jz 2f
    lea rdi, [rsp + 24]
    lea rsi, [rsp + 72]
    call key_before
    test eax, eax
    jz 3f
2:  movdqu xmm0, [rsp + 24]
    movdqu [rsp + 72], xmm0
    mov rax, [rsp + 40]
    mov [rsp + 88], rax
    mov r15d, 1
3:  lea rdi, [rsp]
    lea rsi, [rsp + 24]
    call key_before
    test eax, eax
    jz 4f
    test r14d, r14d
    jz 31f
    lea rdi, [rsp + 24]
    lea rsi, [rsp + 48]
    call key_before
    test eax, eax
    jz 4f
31: movdqu xmm0, [rsp + 24]
    movdqu [rsp + 48], xmm0
    mov rax, [rsp + 40]
    mov [rsp + 64], rax
    mov r14d, 1
4:  inc ebx
    cmp ebx, PN_MAX
    jb 1b
    lea rax, [rsp + 48]
    test r14d, r14d
    jnz 5f
    lea rax, [rsp + 72]         # past the last: round to the first
5:  mov edi, [rax + 16]
    call pn_ptr
    mov rdi, [rax + PN_view]
    call view_index
    test rax, rax
    js 9f
    cmp rax, [rip + g_tab_cur]
    je 9f
    mov rdi, rax
    call app_activate_tab
9:  EPILOGUE

# the active pane trades places with its neighbor on that side; nothing when there is none there
FN cmd_swap_left
    xor edi, edi
    jmp pane_swap
FN cmd_swap_right
    mov edi, 1
    jmp pane_swap
FN cmd_swap_up
    mov edi, 2
    jmp pane_swap
FN cmd_swap_down
    mov edi, 3
    jmp pane_swap

# pane_swap(side 0 left 1 right 2 up 3 down): of the panes beside the active one on that side (their
#   edges a few pixels apart, overlapping it across), the nearest, then the one most in line with it
pane_swap:
    PROLOGUE 16
    mov r15d, edi
    mov rdi, [rip + g_tab_cur]
    test rdi, rdi
    js 9f
    call tab_at
    mov r12, [rax + TAB_group]
    mov rdi, [rax + TAB_id]
    call pn_leaf
    cmp eax, -1
    je 9f
    mov edi, eax
    call pn_ptr
    mov r13, rax                # the active leaf
    mov r14, -1                 # the best key so far
    mov qword ptr [rsp], 0      # its leaf
    xor ebx, ebx
1:  mov edi, ebx
    call pn_ptr
    cmp dword ptr [rax + PN_kind], PN_LEAF
    jne 8f
    cmp [rax + PN_group], r12d
    jne 8f
    cmp rax, r13
    je 8f
    # across: x for left and right, y for up and down; along: the other
    mov r8d, [r13 + PN_y]       # active's span across
    mov r9d, [r13 + PN_h]
    mov r10d, [rax + PN_y]      # the other's
    mov r11d, [rax + PN_h]
    cmp r15d, 2
    jb 2f
    mov r8d, [r13 + PN_x]
    mov r9d, [r13 + PN_w]
    mov r10d, [rax + PN_x]
    mov r11d, [rax + PN_w]
2:  # they overlap across
    lea ecx, [r10 + r11]
    cmp r8d, ecx
    jge 8f
    lea ecx, [r8 + r9]
    cmp r10d, ecx
    jge 8f
    # the gap along: from the active's edge on that side to the other's facing edge
    cmp r15d, 1
    ja 3f
    mov ecx, [rax + PN_x]       # right: other.x - (x + w)
    mov edx, [r13 + PN_x]
    add edx, [r13 + PN_w]
    test r15d, r15d
    jnz 4f
    mov ecx, [r13 + PN_x]       # left: x - (other.x + other.w)
    mov edx, [rax + PN_x]
    add edx, [rax + PN_w]
    jmp 4f
3:  mov ecx, [rax + PN_y]       # down: other.y - (y + h)
    mov edx, [r13 + PN_y]
    add edx, [r13 + PN_h]
    cmp r15d, 3
    je 4f
    mov ecx, [r13 + PN_y]       # up: y - (other.y + other.h)
    mov edx, [rax + PN_y]
    add edx, [rax + PN_h]
4:  sub ecx, edx
    cmp ecx, -4
    jl 8f
    add ecx, 8
    shl rcx, 32
    # in line: the distance between the middles across
    lea edx, [r10 + r10]
    add edx, r11d
    lea esi, [r8 + r8]
    add esi, r9d
    sub edx, esi
    mov esi, edx
    neg esi
    cmovns edx, esi
    or rcx, rdx
    cmp rcx, r14
    jae 8f
    mov r14, rcx
    mov [rsp], rax
8:  inc ebx
    cmp ebx, PN_MAX
    jb 1b
    mov rax, [rsp]
    test rax, rax
    jz 9f
    mov rcx, [rax + PN_view]
    mov rdx, [r13 + PN_view]
    mov [rax + PN_view], rdx
    mov [r13 + PN_view], rcx
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# pn_key(node, key ptr): where a pane is clockwise around the tab's middle (ord_mid), as
#   {double angle, double tie, u32 node}. The angle is a diamond angle, 0 to 4 from the right through
#   below, left and above; the middle itself is -1. Panes in a line from the middle (a row, a column)
#   share an angle and go outward on the right and below, inward on the left and above
pn_key:
    push rsi
    call pn_ptr
    pop rsi
    mov [rsi + 16], edi
    mov ecx, [rax + PN_x]       # dx, doubled
    add ecx, ecx
    add ecx, [rax + PN_w]
    sub ecx, [rip + ord_mid]
    mov edx, [rax + PN_y]       # dy, doubled
    add edx, edx
    add edx, [rax + PN_h]
    sub edx, [rip + ord_mid + 4]
    mov r8d, ecx                # |dx|
    neg r8d
    cmovs r8d, ecx
    mov r9d, edx                # |dy|
    neg r9d
    cmovs r9d, edx
    lea r10d, [r8 + r9]
    test r10d, r10d
    jnz 1f
    mov rax, 0xbff0000000000000 # -1.0
    mov [rsi], rax
    mov qword ptr [rsi + 8], 0
    ret
1:  test edx, edx
    js 2f
    xor eax, eax                # below the middle: right 0, left 1
    mov r11d, r9d
    test ecx, ecx
    jns 3f
    mov eax, 1
    mov r11d, r8d
    jmp 3f
2:  mov eax, 2                  # above: left 2, right 3
    mov r11d, r9d
    test ecx, ecx
    js 3f
    mov eax, 3
    mov r11d, r8d
3:  cvtsi2sd xmm0, r11d
    cvtsi2sd xmm1, r10d
    divsd xmm0, xmm1
    cvtsi2sd xmm1, eax
    addsd xmm0, xmm1
    movsd [rsi], xmm0
    cmp eax, 2
    jb 4f
    neg r10d
4:  cvtsi2sd xmm1, r10d
    movsd [rsi + 8], xmm1
    ret

# key_before(a, b) -> eax 1 when pn_key a comes before b
key_before:
    movsd xmm0, [rdi]
    ucomisd xmm0, [rsi]
    jb 1f
    ja 2f
    movsd xmm0, [rdi + 8]
    ucomisd xmm0, [rsi + 8]
    jb 1f
    ja 2f
    mov ecx, [rdi + 16]
    cmp ecx, [rsi + 16]
    jb 1f
2:  xor eax, eax
    ret
1:  mov eax, 1
    ret

# ---------------- drawing ----------------

# layout(node, x, y, w, h): the rects of a subtree. Two panes share a line a pixel wide; the strip
#   around it is hit tested here, before the panes are drawn (it keeps its press), and a drag moves it
layout:
    PROLOGUE 48
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov r15d, edi
    call pn_ptr
    mov rbx, rax
    mov eax, [rsp]
    mov [rbx + PN_x], eax
    mov eax, [rsp + 4]
    mov [rbx + PN_y], eax
    mov eax, [rsp + 8]
    mov [rbx + PN_w], eax
    mov eax, [rsp + 12]
    mov [rbx + PN_h], eax
    cmp dword ptr [rbx + PN_kind], PN_LEAF
    je .Lly_ret
    M r12d, MI_1                # the line between the two
    # the room along the split, and where it starts
    mov r13d, [rsp + 8]
    mov r14d, [rsp]
    cmp dword ptr [rbx + PN_kind], PN_ROW
    je 1f
    mov r13d, [rsp + 12]
    mov r14d, [rsp + 4]
1:  sub r13d, r12d
    jg 2f
    mov r13d, 1
2:  # a's share, each side keeping some room
    mov eax, [rbx + PN_ratio]
    imul rax, r13
    shr rax, 16
    mov [rsp + 16], eax
    call .Lly_clamp
    # the strip: MI_3 either side of the line
    lea edi, [r15 + ID_PANE_DIV]
    mov eax, [rsp + 16]
    M r9d, MI_3
    cmp dword ptr [rbx + PN_kind], PN_ROW
    jne 3f
    lea esi, [r14 + rax]
    sub esi, r9d
    mov edx, [rsp + 4]
    lea ecx, [r12 + r9*2]
    mov r8d, [rsp + 12]
    jmp 4f
3:  mov esi, [rsp]
    lea edx, [r14 + rax]
    sub edx, r9d
    mov ecx, [rsp + 8]
    lea r8d, [r12 + r9*2]
4:  call ui_btn
    mov [rsp + 20], eax
    mov [rbx + PN_bits], eax
    # the pointer along the split
    mov ecx, [rip + g_mx]
    cmp dword ptr [rbx + PN_kind], PN_ROW
    je 7f
    mov ecx, [rip + g_my]
7:  sub ecx, r14d
    mov eax, [rsp + 20]
    test eax, UB_PRESS
    jz 81f
    and dword ptr [rip + g_pressed], ~(1 << BTN_LEFT)   # the press is the drag's
    sub ecx, [rsp + 16]
    mov [rip + div_grab], ecx
    mov eax, [rip + g_mx]
    mov [rip + div_px], eax
    mov eax, [rip + g_my]
    mov [rip + div_py], eax
    mov dword ptr [rip + div_moved], 0
    jmp 9f
81: test eax, UB_HELD
    jz 9f
    # a press that does not move leaves the line where it is (a double-click swaps the panes)
    cmp dword ptr [rip + div_moved], 0
    jne 82f
    mov eax, [rip + g_mx]
    cmp eax, [rip + div_px]
    jne 811f
    mov eax, [rip + g_my]
    cmp eax, [rip + div_py]
    je 9f
811:mov dword ptr [rip + div_moved], 1
82: sub ecx, [rip + div_grab]
    mov [rsp + 16], ecx
    call .Lly_clamp
    mov eax, [rsp + 16]
    shl rax, 16
    xor edx, edx
    movsxd rcx, r13d
    div rcx
    mov [rbx + PN_ratio], eax
    mov dword ptr [rip + g_dirty], 1
9:  # the two sides
    mov eax, [rsp + 16]
    cmp dword ptr [rbx + PN_kind], PN_ROW
    jne 11f
    mov edi, [rbx + PN_a]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, eax
    mov r8d, [rsp + 12]
    call layout
    mov eax, [rsp + 16]
    add eax, r12d
    mov edi, [rbx + PN_b]
    mov esi, [rsp]
    add esi, eax
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    sub ecx, eax
    mov r8d, [rsp + 12]
    call layout
    jmp .Lly_ret
11: mov edi, [rbx + PN_a]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, eax
    call layout
    mov eax, [rsp + 16]
    add eax, r12d
    mov edi, [rbx + PN_b]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    add edx, eax
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    sub r8d, eax
    call layout
.Lly_ret:
    EPILOGUE
# [rsp + 16] (a's size) kept within the room r13d, some of it left to each side
.Lly_clamp:
    mov eax, [rsp + 8 + 16]
    M ecx, MI_64
    add ecx, ecx
    mov edx, r13d
    sar edx, 1
    cmp ecx, edx
    cmovg ecx, edx              # the least a side keeps
    cmp eax, ecx
    cmovl eax, ecx
    mov edx, r13d
    sub edx, ecx
    cmp eax, edx
    cmovg eax, edx
    mov [rsp + 8 + 16], eax
    ret

# dividers_draw(group): over the panes, the lines between them, each with a small handle at its
#   middle; under the pointer or dragged a line is the accent's, and a double-click on the handle
#   swaps the two sides
dividers_draw:
    PROLOGUE 48
    mov r12d, edi
    lea rbx, [rip + nodes]
    xor r13d, r13d
.Ldd_node:
    cmp dword ptr [rbx + PN_kind], PN_ROW
    jb .Ldd_next
    cmp [rbx + PN_group], r12d
    jne .Ldd_next
    mov edi, [rbx + PN_a]
    call pn_ptr
    mov r14, rax
    # the line's rect
    M eax, MI_1
    cmp dword ptr [rbx + PN_kind], PN_ROW
    jne 1f
    mov ecx, [r14 + PN_x]
    add ecx, [r14 + PN_w]
    mov [rsp], ecx
    mov ecx, [rbx + PN_y]
    mov [rsp + 4], ecx
    mov [rsp + 8], eax
    mov ecx, [rbx + PN_h]
    mov [rsp + 12], ecx
    jmp 2f
1:  mov ecx, [rbx + PN_x]
    mov [rsp], ecx
    mov ecx, [r14 + PN_y]
    add ecx, [r14 + PN_h]
    mov [rsp + 4], ecx
    mov ecx, [rbx + PN_w]
    mov [rsp + 8], ecx
    mov [rsp + 12], eax
2:  mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    COLOR r8d, T_BORDER
    call gfx_fill
    # the handle: MI_4 across, MI_32 along, around the line's middle
    M eax, MI_4
    M ecx, MI_32
    cmp dword ptr [rbx + PN_kind], PN_ROW
    jne 3f
    mov edx, [rsp]
    mov r8d, eax
    sar r8d, 1
    sub edx, r8d
    mov [rsp + 16], edx
    mov edx, [rsp + 12]
    sub edx, ecx
    sar edx, 1
    add edx, [rsp + 4]
    mov [rsp + 20], edx
    mov [rsp + 24], eax
    mov [rsp + 28], ecx
    jmp 4f
3:  mov edx, [rsp + 8]
    sub edx, ecx
    sar edx, 1
    add edx, [rsp]
    mov [rsp + 16], edx
    mov edx, [rsp + 4]
    mov r8d, eax
    sar r8d, 1
    sub edx, r8d
    mov [rsp + 20], edx
    mov [rsp + 24], ecx
    mov [rsp + 28], eax
4:  COLOR edi, T_BORDER
    COLOR esi, T_FG
    mov edx, 90
    call color_mix
    mov r15d, eax               # the handle's color
    test dword ptr [rbx + PN_bits], UB_HOVER | UB_HELD
    jz 6f
    mov ecx, CUR_EW
    cmp dword ptr [rbx + PN_kind], PN_ROW
    je 5f
    mov ecx, CUR_NS
5:  mov [rip + g_cursor], ecx
    COLOR r15d, T_ACCENT
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    mov r8d, r15d
    call gfx_fill
6:  mov edi, [rsp + 16]
    mov esi, [rsp + 20]
    mov edx, [rsp + 24]
    mov ecx, [rsp + 28]
    M r8d, MI_2
    mov r9d, r15d
    call gfx_round_rect
    # a double-click on the handle (a little room around it counts)
    test dword ptr [rbx + PN_bits], UB_DOUBLE
    jz .Ldd_next
    M eax, MI_6
    mov ecx, [rip + g_mx]
    mov edx, [rsp + 16]
    sub edx, eax
    cmp ecx, edx
    jl .Ldd_next
    add edx, [rsp + 24]
    lea edx, [rdx + rax*2]
    cmp ecx, edx
    jge .Ldd_next
    mov ecx, [rip + g_my]
    mov edx, [rsp + 20]
    sub edx, eax
    cmp ecx, edx
    jl .Ldd_next
    add edx, [rsp + 28]
    lea edx, [rdx + rax*2]
    cmp ecx, edx
    jge .Ldd_next
    mov eax, [rbx + PN_a]
    mov ecx, [rbx + PN_b]
    mov [rbx + PN_a], ecx
    mov [rbx + PN_b], eax
    mov eax, 65536
    sub eax, [rbx + PN_ratio]
    mov [rbx + PN_ratio], eax
    mov dword ptr [rip + g_active], 0
    mov dword ptr [rip + g_dirty], 1
.Ldd_next:
    add rbx, PN_SIZE
    inc r13d
    cmp r13d, PN_MAX
    jb .Ldd_node
    EPILOGUE

# in_rect(rect ptr) -> eax 1 when the pointer is in it
in_rect:
    xor eax, eax
    mov ecx, [rip + g_mx]
    mov edx, [rip + g_my]
    cmp ecx, [rdi]
    jl 1f
    cmp edx, [rdi + 4]
    jl 1f
    sub ecx, [rdi]
    sub edx, [rdi + 4]
    cmp ecx, [rdi + 8]
    jge 1f
    cmp edx, [rdi + 12]
    jge 1f
    mov eax, 1
1:  ret

# panes_draw(x, y, w, h): the views of the active tab
FN panes_draw
    PROLOGUE 48
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    mov qword ptr [rip + drop_view], 0
    mov rdi, [rip + g_tab_cur]
    call tab_at
    mov r12, [rax + TAB_group]
    mov [rip + cur_group], r12d
    mov r13, [rax + TAB_id]
    mov edi, r12d
    call pn_root
    cmp dword ptr [rip + g_zen], 0
    jne 0f                      # zen mode: the view with the keys alone
    cmp eax, -1
    jne .Lpd_tree
0:  # one view has the tab
    mov eax, [rsp]
    mov [rip + solo], eax
    mov eax, [rsp + 4]
    mov [rip + solo + 4], eax
    mov eax, [rsp + 8]
    mov [rip + solo + 8], eax
    mov eax, [rsp + 12]
    mov [rip + solo + 12], eax
    lea rdi, [rip + solo]
    mov rsi, r13
    call drop_probe
    mov rdi, [rip + g_tab_cur]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    xor r9d, r9d
    call view_draw
    jmp .Lpd_drop
.Lpd_tree:
    mov edi, eax
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 12]
    call layout
    # a press on a pane gives it the keys before anything is drawn
    cmp dword ptr [rip + g_block], 0
    jne 3f
    cmp dword ptr [rip + g_pressed], 0
    je 3f
    lea rbx, [rip + nodes]
    xor r14d, r14d
1:  cmp dword ptr [rbx + PN_kind], PN_LEAF
    jne 2f
    cmp [rbx + PN_group], r12d
    jne 2f
    lea rdi, [rbx + PN_x]
    call in_rect
    test eax, eax
    jz 2f
    mov rdi, [rbx + PN_view]
    call view_index
    test rax, rax
    js 3f
    cmp rax, [rip + g_tab_cur]
    je 3f
    mov rdi, rax
    call app_activate_tab
    jmp 3f
2:  add rbx, PN_SIZE
    inc r14d
    cmp r14d, PN_MAX
    jb 1b
3:  # the others first, the one with the keys last: its state is what the frame leaves behind
    mov dword ptr [rsp + 16], 0 # pass
.Lpd_pass:
    lea rbx, [rip + nodes]
    xor r14d, r14d
4:  cmp dword ptr [rbx + PN_kind], PN_LEAF
    jne 6f
    cmp [rbx + PN_group], r12d
    jne 6f
    mov rdi, [rbx + PN_view]
    call view_index
    test rax, rax
    js 6f
    mov r15, rax
    xor ecx, ecx
    cmp rax, [rip + g_tab_cur]
    sete cl
    cmp ecx, [rsp + 16]
    jne 6f
    test ecx, ecx
    jnz 5f
    lea rdi, [rbx + PN_x]
    mov rsi, [rbx + PN_view]
    call drop_probe
    jmp 51f
5:  lea rdi, [rbx + PN_x]
    mov rsi, [rbx + PN_view]
    call drop_probe
51: mov rdi, r15
    mov esi, [rbx + PN_x]
    mov edx, [rbx + PN_y]
    mov ecx, [rbx + PN_w]
    mov r8d, [rbx + PN_h]
    mov r9d, 1
    call view_draw
6:  add rbx, PN_SIZE
    inc r14d
    cmp r14d, PN_MAX
    jb 4b
    inc dword ptr [rsp + 16]
    cmp dword ptr [rsp + 16], 2
    jb .Lpd_pass
    mov edi, r12d
    call dividers_draw
.Lpd_drop:
    call drop_draw
    EPILOGUE

# ---------------- a file dragged from the explorer ----------------

# pane_drag_begin(path): the explorer's row is being dragged
FN pane_drag_begin
    push rbx
    mov rbx, rdi
    call strlen
    cmp rax, DRAG_MAX - 1
    jae 1f
    lea rdi, [rip + drag_path]
    mov rsi, rbx
    call cstr_copy
    mov dword ptr [rip + g_drag_on], 1
    mov dword ptr [rip + g_dirty], 1
1:  pop rbx
    ret

# drop_probe(rect ptr, view id): when the dragged file is over this pane, the side it would take
drop_probe:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    cmp dword ptr [rip + g_drag_on], 0
    je 9f
    call in_rect
    test eax, eax
    jz 9f
    mov [rip + drop_view], r12
    # the nearest edge, as a share of the pane; the middle third takes the whole pane
    mov eax, [rip + g_mx]
    sub eax, [rbx]
    imul eax, eax, 1000
    cdq
    idiv dword ptr [rbx + 8]
    mov r13d, eax               # x, of 1000
    mov eax, [rip + g_my]
    sub eax, [rbx + 4]
    imul eax, eax, 1000
    cdq
    idiv dword ptr [rbx + 12]
    mov r14d, eax               # y
    mov ecx, r13d               # the least distance, and its side
    mov edx, SPLIT_LEFT
    mov eax, 1000
    sub eax, r13d
    cmp eax, ecx
    jge 1f
    mov ecx, eax
    mov edx, SPLIT_RIGHT
1:  cmp r14d, ecx
    jge 2f
    mov ecx, r14d
    mov edx, SPLIT_UP
2:  mov eax, 1000
    sub eax, r14d
    cmp eax, ecx
    jge 3f
    mov ecx, eax
    mov edx, SPLIT_DOWN
3:  cmp ecx, 300
    jle 4f
    xor edx, edx
4:  mov [rip + drop_dir], edx
    # the rect the file would take
    mov eax, [rbx]
    mov [rip + drop_rect], eax
    mov eax, [rbx + 4]
    mov [rip + drop_rect + 4], eax
    mov eax, [rbx + 8]
    mov [rip + drop_rect + 8], eax
    mov eax, [rbx + 12]
    mov [rip + drop_rect + 12], eax
    mov eax, [rbx + 8]
    sar eax, 1
    mov ecx, [rbx + 12]
    sar ecx, 1
    cmp edx, SPLIT_LEFT
    jne 5f
    mov [rip + drop_rect + 8], eax
5:  cmp edx, SPLIT_RIGHT
    jne 6f
    add [rip + drop_rect], eax
    mov r8d, [rbx + 8]
    sub r8d, eax
    mov [rip + drop_rect + 8], r8d
6:  cmp edx, SPLIT_UP
    jne 7f
    mov [rip + drop_rect + 12], ecx
7:  cmp edx, SPLIT_DOWN
    jne 9f
    add [rip + drop_rect + 4], ecx
    mov r8d, [rbx + 12]
    sub r8d, ecx
    mov [rip + drop_rect + 12], r8d
9:  EPILOGUE

# drop_draw(): where the dragged file would go, its name at the pointer, and the drop itself
drop_draw:
    PROLOGUE 16
    cmp dword ptr [rip + g_drag_on], 0
    je 9f
    mov dword ptr [rip + g_cursor], CUR_POINTER
    cmp qword ptr [rip + drop_view], 0
    je 1f
    M eax, MI_4
    mov edi, [rip + drop_rect]
    add edi, eax
    mov esi, [rip + drop_rect + 4]
    add esi, eax
    mov edx, [rip + drop_rect + 8]
    sub edx, eax
    sub edx, eax
    mov ecx, [rip + drop_rect + 12]
    sub ecx, eax
    sub ecx, eax
    mov [rsp], edi
    mov [rsp + 4], esi
    mov [rsp + 8], edx
    mov [rsp + 12], ecx
    COLOR edi, T_ACCENT
    mov esi, 56
    call color_alpha
    mov r9d, eax
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    xor r8d, r8d
    call gfx_round_rect
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    xor r8d, r8d
    COLOR r9d, T_ACCENT
    push 0
    push 0
    call gfx_card_edge_keep
    add rsp, 16
1:  # the file's name beside the pointer
    lea rdi, [rip + drag_path]
    call path_base
    mov r12, rax
    mov rdi, rax
    call strlen
    lea rdi, [rip + g_face_small]
    mov rsi, r12
    mov rdx, rax
    call text_width
    mov r13d, eax
    add r13d, [rip + g_mt + 4*MI_16]
    mov edi, [rip + g_mx]
    add edi, [rip + g_mt + 4*MI_12]
    mov esi, [rip + g_my]
    add esi, [rip + g_mt + 4*MI_12]
    mov [rsp], edi
    mov [rsp + 4], esi
    mov edx, r13d
    M ecx, MI_24
    M r8d, MI_RADIUS
    COLOR r9d, T_BORDER
    COLOR eax, T_POPUP
    push rax
    push rax
    call gfx_frame
    add rsp, 16
    lea rdi, [rip + g_face_small]
    mov esi, [rsp]
    add esi, [rip + g_mt + 4*MI_8]
    mov edx, [rsp + 4]
    M ecx, MI_24
    mov r8, r12
    COLOR r9d, T_FG
    call ui_text_c
    # the button let go: over a pane the file opens there
    test dword ptr [rip + g_released], 1 << BTN_LEFT
    jz 9f
    mov dword ptr [rip + g_drag_on], 0
    mov dword ptr [rip + g_dirty], 1
    mov rdi, [rip + drop_view]
    test rdi, rdi
    jz 9f
    lea rdi, [rip + drag_path]
    mov rsi, [rip + drop_view]
    mov edx, [rip + drop_dir]
    call app_drop_file
9:  EPILOGUE

# panes_drag_end(): the frame is drawn: a drag let go anywhere is over
FN panes_drag_end
    cmp dword ptr [rip + g_drag_on], 0
    je 1f
    test dword ptr [rip + g_mdown], 1 << BTN_LEFT
    jnz 1f
    mov dword ptr [rip + g_drag_on], 0
    mov dword ptr [rip + g_dirty], 1
1:  ret

# path_base(path) -> rax its last component
path_base:
    mov rax, rdi
1:  mov cl, [rdi]
    test cl, cl
    jz 3f
    inc rdi
    cmp cl, '/'
    je 2f
    cmp cl, 92
    jne 1b
2:  cmp byte ptr [rdi], 0
    je 1b
    mov rax, rdi
    jmp 1b
3:  ret

# gfx_card_edge_keep(x, y, w, h, r, border, [0]): the outline alone of a rounded rect already drawn
gfx_card_edge_keep:
    PROLOGUE 16
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov r15d, ecx
    # the four straight sides, between the corners
    mov ebx, r8d
    mov [rsp], r9d
    lea edi, [r12 + rbx]
    mov esi, r13d
    mov edx, r14d
    sub edx, ebx
    sub edx, ebx
    mov ecx, [rip + g_border]
    mov r8d, [rsp]
    call gfx_fill
    lea edi, [r12 + rbx]
    lea esi, [r13 + r15]
    sub esi, [rip + g_border]
    mov edx, r14d
    sub edx, ebx
    sub edx, ebx
    mov ecx, [rip + g_border]
    mov r8d, [rsp]
    call gfx_fill
    mov edi, r12d
    lea esi, [r13 + rbx]
    mov edx, [rip + g_border]
    mov ecx, r15d
    sub ecx, ebx
    sub ecx, ebx
    mov r8d, [rsp]
    call gfx_fill
    lea edi, [r12 + r14]
    sub edi, [rip + g_border]
    lea esi, [r13 + rbx]
    mov edx, [rip + g_border]
    mov ecx, r15d
    sub ecx, ebx
    sub ecx, ebx
    mov r8d, [rsp]
    call gfx_fill
    EPILOGUE
