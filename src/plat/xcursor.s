# xcursor: cursor images from the user's Xcursor theme, for compositors that cannot draw named cursors.
# Lookup follows libXcursor: XCURSOR_THEME (else "default") and its Inherits=, then "default",
# in XCURSOR_PATH or ~/.local/share/icons ~/.icons /usr/share/icons /usr/share/pixmaps.
.include "raftaar.inc"

.equ XC_IMAGE, 0xfffd0002
.equ XC_MAGIC, 0x72756358       # "Xcur"

.bss
.p2align 3
dirs: .zero SB_SIZE             # NUL separated, ends with an empty entry
pb: .zero SB_SIZE               # path scratch
.globl g_xcursor_found
g_xcursor_found: .zero SB_SIZE  # file the last successful lookup read (print-cursor)
dirs_done: .long 0

.text

# xcursor_size() -> eax nominal size in logical pixels (XCURSOR_SIZE, default 24)
FN xcursor_size
    sub rsp, 8
    lea rdi, [rip + .Lenv_size]
    call getenv
    mov ecx, 24
    test rax, rax
    jz 1f
    mov rdi, rax
    call strlen
    mov rsi, rax
    call parse_u64
    mov ecx, eax
    test rdx, rdx
    jnz 1f
    mov ecx, 24
1:  cmp ecx, 8
    jge 2f
    mov ecx, 8
2:  cmp ecx, 256
    jle 3f
    mov ecx, 256
3:  mov eax, ecx
    add rsp, 8
    ret

# xcursor_load(shape CUR_*, size in pixels, XC*) -> 1 if a theme had it (XC_file must be mem_free'd)
FN xcursor_load
    PROLOGUE 16
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    call dirs_init
    lea rdi, [rip + .Lenv_theme]
    call getenv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    jne 2f
1:  lea rax, [rip + .Ldefault]
2:  mov r14, rax                # theme
.Lxl_theme:
    lea rax, [rip + shape_names]
    mov r15, [rax + rbx*8]      # names for this shape
.Lxl_name:
    mov rsi, [r15]
    test rsi, rsi
    jz .Lxl_next_theme
    mov rdi, r14
    xor edx, edx
    call find
    test rax, rax
    jz 3f
    mov rdi, rax
    mov rsi, rdx
    mov edx, r12d
    mov rcx, r13
    call parse
    test eax, eax
    jnz 9f
3:  add r15, 8
    jmp .Lxl_name
.Lxl_next_theme:
    # then the "default" theme, unless that was the one
    mov rdi, r14
    lea rsi, [rip + .Ldefault]
    call strcmp_eq
    test eax, eax
    jnz 8f
    lea r14, [rip + .Ldefault]
    jmp .Lxl_theme
8:  xor eax, eax
9:  EPILOGUE

# find(theme, name, depth) -> rax file contents (mem_alloc'd) or 0, rdx length
find:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov [rsp], edx
    cmp edx, 5
    jae .Lf_none
    # <dir>/<theme>/cursors/<name> in every directory
    lea r14, [rip + dirs]
    mov r14, [r14 + SB_ptr]
1:  cmp byte ptr [r14], 0
    je .Lf_inherit
    mov rdi, r14
    mov rsi, r12
    lea rdx, [rip + .Lcursors]
    mov rcx, r13
    call mkpath
    mov rdi, [rip + pb + SB_ptr]
    call file_read_all
    test rax, rax
    jnz .Lf_found
    mov rdi, r14
    call strlen
    lea r14, [r14 + rax + 1]
    jmp 1b
.Lf_inherit:
    # the first index.theme found names the parents
    lea r14, [rip + dirs]
    mov r14, [r14 + SB_ptr]
2:  cmp byte ptr [r14], 0
    je .Lf_none
    mov rdi, r14
    mov rsi, r12
    lea rdx, [rip + .Lindex]
    xor ecx, ecx
    call mkpath
    mov rdi, [rip + pb + SB_ptr]
    call file_read_all
    test rax, rax
    jnz 3f
    mov rdi, r14
    call strlen
    lea r14, [r14 + rax + 1]
    jmp 2b
3:  mov r15, rax                # index.theme text
    mov rdi, rax
    lea rsi, [rip + .Linherits]
    call find_key
    test rax, rax
    jz .Lf_free
    mov rbx, rax
    # names separated by , ; or blanks; cut them in place
4:  movzx eax, byte ptr [rbx]
    test al, al
    jz .Lf_free
    cmp al, 10
    je .Lf_free
    cmp al, 13
    je .Lf_free
    cmp al, ','
    je 5f
    cmp al, ';'
    je 5f
    cmp al, ' '
    je 5f
    cmp al, 9
    jne 6f
5:  inc rbx
    jmp 4b
6:  mov rcx, rbx
7:  movzx eax, byte ptr [rcx]
    test al, al
    jz 8f
    cmp al, 10
    je 8f
    cmp al, 13
    je 8f
    cmp al, ','
    je 8f
    cmp al, ';'
    je 8f
    cmp al, ' '
    je 8f
    cmp al, 9
    je 8f
    inc rcx
    jmp 7b
8:  mov [rsp + 8], al           # separator we overwrite
    mov byte ptr [rcx], 0
    push rcx
    push rcx
    mov rdi, rbx
    mov rsi, r13
    mov edx, [rsp + 16]
    inc edx
    call find
    pop rcx
    pop rcx
    test rax, rax
    jnz .Lf_inherited
    mov al, [rsp + 8]
    mov [rcx], al
    test al, al
    jz .Lf_free
    cmp al, 10
    je .Lf_free
    cmp al, 13
    je .Lf_free
    lea rbx, [rcx + 1]
    jmp 4b
.Lf_inherited:
    mov r12, rax
    mov r13, rdx
    mov rdi, r15
    call mem_free
    mov rax, r12
    mov rdx, r13
    EPILOGUE
.Lf_free:
    mov rdi, r15
    call mem_free
.Lf_none:
    xor eax, eax
    xor edx, edx
    EPILOGUE
.Lf_found:
    mov r12, rax
    mov r13, rdx
    lea rdi, [rip + g_xcursor_found]
    call sb_clear
    lea rdi, [rip + g_xcursor_found]
    mov rsi, [rip + pb + SB_ptr]
    call sb_push_cstr
    lea rdi, [rip + g_xcursor_found]
    xor esi, esi
    call sb_push_byte
    mov rax, r12
    mov rdx, r13
    EPILOGUE

# mkpath(dir, theme, middle, name or 0): pb = dir/theme/middle[/name]
mkpath:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    lea rdi, [rip + pb]
    call sb_clear
    lea rdi, [rip + pb]
    mov rsi, rbx
    call sb_push_cstr
    lea rdi, [rip + pb]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + pb]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + pb]
    mov rsi, r13
    call sb_push_cstr
    test r14, r14
    jz 1f
    lea rdi, [rip + pb]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + pb]
    mov rsi, r14
    call sb_push_cstr
1:  lea rdi, [rip + pb]
    xor esi, esi
    call sb_push_byte
    EPILOGUE

# find_key(text, "Key=") -> pointer after "Key=" at the start of a line, or 0
find_key:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call strlen
    mov r13, rax
1:  cmp byte ptr [rbx], 0
    je 8f
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r12
    mov rcx, r13
    call str_starts
    test eax, eax
    jnz 9f
2:  movzx eax, byte ptr [rbx]
    test al, al
    jz 8f
    inc rbx
    cmp al, 10
    jne 2b
    jmp 1b
8:  xor eax, eax
    EPILOGUE
9:  lea rax, [rbx + r13]
    EPILOGUE

# parse(file, len, size, XC*) -> 1 if it holds an image; picks the nominal size closest to size
parse:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    cmp r12, 16
    jb .Lp_bad
    cmp dword ptr [rbx], XC_MAGIC
    jne .Lp_bad
    mov eax, [rbx + 4]          # header size: the table follows
    mov ecx, [rbx + 12]         # entries
    cmp ecx, 0x10000
    ja .Lp_bad
    imul rdx, rcx, 12
    add rdx, rax
    cmp rdx, r12
    ja .Lp_bad
    lea r15, [rbx + rax]        # table
    # closest nominal size
    mov r8d, -1                 # best size
    mov r9d, 0x7fffffff         # its distance
    xor edx, edx
1:  cmp edx, ecx
    jae 3f
    imul r10, rdx, 12
    cmp dword ptr [r15 + r10], XC_IMAGE
    jne 2f
    mov eax, [r15 + r10 + 4]
    mov r11d, eax
    sub r11d, r13d
    mov esi, r11d
    neg esi
    cmovns r11d, esi
    cmp r11d, r9d
    jge 2f
    mov r9d, r11d
    mov r8d, eax
2:  inc edx
    jmp 1b
3:  cmp r8d, -1
    je .Lp_bad
    # first image of that size
    xor edx, edx
4:  cmp edx, ecx
    jae .Lp_bad
    imul r10, rdx, 12
    cmp dword ptr [r15 + r10], XC_IMAGE
    jne 5f
    cmp [r15 + r10 + 4], r8d
    je 6f
5:  inc edx
    jmp 4b
6:  mov eax, [r15 + r10 + 8]    # chunk position
    lea rdx, [rax + 36]
    cmp rdx, r12
    ja .Lp_bad
    lea rsi, [rbx + rax]        # chunk
    mov ecx, [rsi + 16]         # width
    mov edx, [rsi + 20]         # height
    test ecx, ecx
    jz .Lp_bad
    test edx, edx
    jz .Lp_bad
    cmp ecx, 1024
    ja .Lp_bad
    cmp edx, 1024
    ja .Lp_bad
    mov r8d, [rsi]              # chunk header size
    cmp r8d, 36
    jb .Lp_bad
    mov r9d, ecx
    imul r9d, edx
    shl r9, 2
    add r9, rax
    add r9, r8
    cmp r9, r12
    ja .Lp_bad
    mov [r14 + XC_file], rbx
    add r8, rsi
    mov [r14 + XC_pixels], r8
    mov [r14 + XC_w], ecx
    mov [r14 + XC_h], edx
    mov eax, [rsi + 24]
    mov [r14 + XC_xhot], eax
    mov eax, [rsi + 28]
    mov [r14 + XC_yhot], eax
    mov eax, 1
    EPILOGUE
.Lp_bad:
    mov rdi, rbx
    call mem_free
    xor eax, eax
    EPILOGUE

# dirs_init(): search path, once
dirs_init:
    PROLOGUE 16
    cmp dword ptr [rip + dirs_done], 0
    jne 9f
    mov dword ptr [rip + dirs_done], 1
    lea rdi, [rip + .Lenv_path]
    call getenv
    test rax, rax
    jz .Ldi_default
    # colon separated, ~/ is the home directory
    mov rbx, rax
1:  cmp byte ptr [rbx], 0
    je 8f
    cmp byte ptr [rbx], ':'
    jne 2f
    inc rbx
    jmp 1b
2:  cmp word ptr [rbx], 0x2f7e  # "~/"
    jne 3f
    lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz 3f
    lea rdi, [rip + dirs]
    mov rsi, rax
    call sb_push_cstr
    inc rbx
3:  movzx eax, byte ptr [rbx]
    test al, al
    jz 4f
    cmp al, ':'
    je 4f
    lea rdi, [rip + dirs]
    movzx esi, al
    call sb_push_byte
    inc rbx
    jmp 3b
4:  lea rdi, [rip + dirs]
    xor esi, esi
    call sb_push_byte
    jmp 1b
.Ldi_default:
    # $XDG_DATA_HOME/icons (~/.local/share/icons), ~/.icons, then the system directories
    lea rdi, [rip + .Lenv_data]
    call getenv
    test rax, rax
    jz 5f
    cmp byte ptr [rax], 0
    je 5f
    lea rdi, [rip + dirs]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + dirs]
    lea rsi, [rip + .Licons]
    call sb_push_cstr
    lea rdi, [rip + dirs]
    xor esi, esi
    call sb_push_byte
    jmp 6f
5:  lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz 7f
    lea rdi, [rip + dirs]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + dirs]
    lea rsi, [rip + .Llocal_icons]
    call sb_push_cstr
    lea rdi, [rip + dirs]
    xor esi, esi
    call sb_push_byte
6:  lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz 7f
    lea rdi, [rip + dirs]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + dirs]
    lea rsi, [rip + .Ldot_icons]
    call sb_push_cstr
    lea rdi, [rip + dirs]
    xor esi, esi
    call sb_push_byte
7:  lea rdi, [rip + dirs]
    lea rsi, [rip + .Lsys_icons]
    call sb_push_cstr
    lea rdi, [rip + dirs]
    xor esi, esi
    call sb_push_byte
    lea rdi, [rip + dirs]
    lea rsi, [rip + .Lsys_pixmaps]
    call sb_push_cstr
    lea rdi, [rip + dirs]
    xor esi, esi
    call sb_push_byte
8:  lea rdi, [rip + dirs]
    xor esi, esi
    call sb_push_byte
9:  EPILOGUE

# xcursor_builtin(shape, size, XC*) -> 1; an outlined arrow or I-beam, scaled to size
FN xcursor_builtin
    PROLOGUE 32
    mov r12d, esi
    mov r13, rdx
    lea rbx, [rip + .Larrow]
    cmp edi, CUR_TEXT
    jne 1f
    lea rbx, [rip + .Libeam]
1:  # scale factor: the patterns are drawn for 24 px
    lea eax, [r12 + 12]
    xor edx, edx
    mov ecx, 24
    div ecx
    test eax, eax
    jnz 2f
    mov eax, 1
2:  mov r14d, eax               # k
    movzx eax, byte ptr [rbx]   # pattern w
    movzx ecx, byte ptr [rbx + 1]
    add eax, 2                  # one pixel of outline around
    add ecx, 2
    mov [rsp], eax              # base w
    mov [rsp + 4], ecx          # base h
    imul eax, r14d
    imul ecx, r14d
    mov [rsp + 8], eax          # w
    mov [rsp + 12], ecx         # h
    imul eax, ecx
    lea rdi, [rax*4]
    call mem_alloc
    mov r15, rax
    mov [r13 + XC_file], rax
    mov [r13 + XC_pixels], rax
    mov eax, [rsp + 8]
    mov [r13 + XC_w], eax
    mov eax, [rsp + 12]
    mov [r13 + XC_h], eax
    movzx eax, byte ptr [rbx + 2]
    inc eax
    imul eax, r14d
    mov [r13 + XC_xhot], eax
    movzx eax, byte ptr [rbx + 3]
    inc eax
    imul eax, r14d
    mov [r13 + XC_yhot], eax
    # every output pixel: black inside the pattern, white next to it, else clear
    xor r12d, r12d              # y
3:  cmp r12d, [rsp + 12]
    jae 9f
    xor r13d, r13d              # x
4:  cmp r13d, [rsp + 8]
    jae 8f
    mov eax, r12d
    xor edx, edx
    div r14d
    mov [rsp + 20], eax         # base y (with the border)
    mov eax, r13d
    xor edx, edx
    div r14d
    mov [rsp + 16], eax         # base x
    mov edi, eax
    mov esi, [rsp + 20]
    call pat_at
    mov ecx, 0xff000000
    test eax, eax
    jnz 7f
    # white if any neighbour is set
    mov dword ptr [rsp + 24], -1
5:  mov dword ptr [rsp + 28], -1
6:  mov edi, [rsp + 16]
    add edi, [rsp + 28]
    mov esi, [rsp + 20]
    add esi, [rsp + 24]
    call pat_at
    mov ecx, 0xffffffff
    test eax, eax
    jnz 7f
    inc dword ptr [rsp + 28]
    cmp dword ptr [rsp + 28], 1
    jle 6b
    inc dword ptr [rsp + 24]
    cmp dword ptr [rsp + 24], 1
    jle 5b
    xor ecx, ecx
7:  mov eax, r12d
    imul eax, [rsp + 8]
    add eax, r13d
    mov [r15 + rax*4], ecx
    inc r13d
    jmp 4b
8:  inc r12d
    jmp 3b
9:  mov eax, 1
    EPILOGUE

# pat_at(x, y) in bordered pattern coordinates -> 1 if the pattern (rbx) is set there
pat_at:
    dec edi
    dec esi
    movzx ecx, byte ptr [rbx]
    cmp edi, ecx
    jae 1f
    movzx edx, byte ptr [rbx + 1]
    cmp esi, edx
    jae 1f
    imul esi, ecx
    add esi, edi
    xor eax, eax
    cmp byte ptr [rbx + 4 + rsi], '#'
    sete al
    ret
1:  xor eax, eax
    ret

.section .rodata
.p2align 3
# CUR_* -> names to try, CSS names first
shape_names: .quad .Ln_default, .Ln_text, .Ln_pointer, .Ln_ew, .Ln_ns, .Ln_nwse, .Ln_nesw, .Ln_default
.Ln_default: .quad .Ls_default, .Ls_left_ptr, .Ls_arrow, 0
.Ln_text: .quad .Ls_text, .Ls_xterm, .Ls_ibeam, 0
.Ln_pointer: .quad .Ls_pointer, .Ls_hand2, .Ls_hand1, .Ls_pointing_hand, 0
.Ln_ew: .quad .Ls_ew, .Ls_sb_h, .Ls_h_double, .Ls_col, 0
.Ln_ns: .quad .Ls_ns, .Ls_sb_v, .Ls_v_double, .Ls_row, 0
.Ln_nwse: .quad .Ls_nwse, .Ls_bd_double, .Ls_size_fdiag, .Ls_br_corner, 0
.Ln_nesw: .quad .Ls_nesw, .Ls_fd_double, .Ls_size_bdiag, .Ls_bl_corner, 0
.Ls_default: .asciz "default"
.Ls_left_ptr: .asciz "left_ptr"
.Ls_arrow: .asciz "arrow"
.Ls_text: .asciz "text"
.Ls_xterm: .asciz "xterm"
.Ls_ibeam: .asciz "ibeam"
.Ls_pointer: .asciz "pointer"
.Ls_hand2: .asciz "hand2"
.Ls_hand1: .asciz "hand1"
.Ls_pointing_hand: .asciz "pointing_hand"
.Ls_ew: .asciz "ew-resize"
.Ls_sb_h: .asciz "sb_h_double_arrow"
.Ls_h_double: .asciz "h_double_arrow"
.Ls_col: .asciz "col-resize"
.Ls_ns: .asciz "ns-resize"
.Ls_sb_v: .asciz "sb_v_double_arrow"
.Ls_v_double: .asciz "v_double_arrow"
.Ls_row: .asciz "row-resize"
.Ls_nwse: .asciz "nwse-resize"
.Ls_bd_double: .asciz "bd_double_arrow"
.Ls_size_fdiag: .asciz "size_fdiag"
.Ls_br_corner: .asciz "bottom_right_corner"
.Ls_nesw: .asciz "nesw-resize"
.Ls_fd_double: .asciz "fd_double_arrow"
.Ls_size_bdiag: .asciz "size_bdiag"
.Ls_bl_corner: .asciz "bottom_left_corner"
.Ldefault: .asciz "default"
.Lcursors: .asciz "/cursors"
.Lindex: .asciz "/index.theme"
.Linherits: .asciz "Inherits="
.Lenv_theme: .asciz "XCURSOR_THEME"
.Lenv_size: .asciz "XCURSOR_SIZE"
.Lenv_path: .asciz "XCURSOR_PATH"
.Lenv_data: .asciz "XDG_DATA_HOME"
.Lhome: .asciz "HOME"
.Licons: .asciz "/icons"
.Llocal_icons: .asciz "/.local/share/icons"
.Ldot_icons: .asciz "/.icons"
.Lsys_icons: .asciz "/usr/share/icons"
.Lsys_pixmaps: .asciz "/usr/share/pixmaps"
# built-in patterns: width, height, hot x, hot y, rows ('#' set)
.Larrow:
    .byte 11, 17, 0, 0
    .ascii "#          "
    .ascii "##         "
    .ascii "###        "
    .ascii "####       "
    .ascii "#####      "
    .ascii "######     "
    .ascii "#######    "
    .ascii "########   "
    .ascii "#########  "
    .ascii "########## "
    .ascii "###########"
    .ascii "######     "
    .ascii "###  ###   "
    .ascii "##   ###   "
    .ascii "#     ###  "
    .ascii "      ###  "
    .ascii "       ##  "
.Libeam:
    .byte 5, 17, 2, 8
    .ascii "## ##"
    .ascii "  #  "
    .ascii "  #  "
    .ascii "  #  "
    .ascii "  #  "
    .ascii "  #  "
    .ascii "  #  "
    .ascii "  #  "
    .ascii "  #  "
    .ascii "  #  "
    .ascii "  #  "
    .ascii "  #  "
    .ascii "  #  "
    .ascii "  #  "
    .ascii "  #  "
    .ascii "  #  "
    .ascii "## ##"
