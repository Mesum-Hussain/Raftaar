# explorer file icons: a file name to an icon and a theme color (assets/icons/files)
.include "raftaar.inc"

.equ FI_READ, 0x10000           # GR_ficon: the grammar's icon key was read
.equ FI_NONE, 0x20000           # and it names no icon
.equ FI_GREY, 8                 # color_names index
.equ COLOR_NAMES, 11            # color_names entries

.text

# file_icon(name cstr) -> eax icon, edx theme color slot. The name is a file's, not a path. A whole
# name beats an extension, and file_types (ignoring case) the grammars: file_types' names, then a
# grammar's (its icon key), then file_types' extensions, then a grammar's *.suffix, then the default
FN file_icon
    PROLOGUE 16
    mov rbx, rdi
    call strlen
    mov r12, rax
    mov rdi, rbx
    mov rsi, r12
    call syntax_for_name
    mov [rsp], rax              # the grammar
    mov [rsp + 8], rdx          # SN_EXACT for its exact name
    lea r13, [rip + file_types]
    # rows: length, 1 for an extension, icon, color, pattern; the whole names come first
1:  movzx ecx, byte ptr [r13]
    test ecx, ecx
    jz 4f
    cmp byte ptr [r13 + 1], 0
    jne 2f
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [r13 + 4]
    call str_ieq
    test eax, eax
    jnz 8f
    movzx eax, byte ptr [r13]
    lea r13, [r13 + rax + 4]
    jmp 1b
2:  cmp qword ptr [rsp + 8], SN_EXACT    # -1 when no grammar fits
    jl 21f
    mov rdi, [rsp]
    call grammar_icon
    test eax, eax
    jns 9f
21: mov rdi, rbx
    mov rsi, r12
    call path_ext
    mov r14, rax
    mov r15, rdx
    test r15, r15
    jz 4f
3:  movzx ecx, byte ptr [r13]
    test ecx, ecx
    jz 4f
    mov rdi, r14
    mov rsi, r15
    lea rdx, [r13 + 4]
    call str_ieq
    test eax, eax
    jnz 8f
    movzx eax, byte ptr [r13]
    lea r13, [r13 + rax + 4]
    jmp 3b
4:  mov rdi, [rsp]
    test rdi, rdi
    jz 5f
    call grammar_icon
    test eax, eax
    jns 9f
5:  mov eax, IC_F_DEFAULT + FI_GREY * 256
    jmp 9f
8:  movzx eax, byte ptr [r13 + 2]
    movzx edx, byte ptr [r13 + 3]
    shl edx, 8
    or eax, edx
    # eax: icon | color << 8
9:  mov edx, eax
    shr edx, 8
    and edx, 0xff
    add edx, T_ICON
    and eax, 0xff
    EPILOGUE

# grammar_icon(gr) -> eax icon | color << 8 from the grammar's icon key ("rust orange"; grey when
# the color is missing or unknown), or -1 for no icon or an unknown one. Read once per grammar.
grammar_icon:
    PROLOGUE
    mov rbx, rdi
    mov eax, [rbx + GR_ficon]
    test eax, eax
    jnz 7f
    mov r12, [rbx + GR_icon]
    mov rdi, r12
    call strlen
    mov r13, rax
    mov rdi, r12
    mov rsi, r13
    call next_word
    test rdx, rdx
    jz 6f
    add r12, rcx
    sub r13, rcx
    mov rdi, rax
    mov rsi, rdx
    call icon_by_name
    test eax, eax
    js 6f
    mov r14d, eax
    mov rdi, r12
    mov rsi, r13
    call next_word
    mov r15d, FI_GREY
    test rdx, rdx
    jz 5f
    mov rdi, rax
    mov rsi, rdx
    call color_by_name
    test eax, eax
    js 5f
    mov r15d, eax
5:  shl r15d, 8
    mov eax, r14d
    add eax, r15d
    add eax, FI_READ
    mov [rbx + GR_ficon], eax
    jmp 7f
6:  mov eax, FI_READ + FI_NONE
    mov [rbx + GR_ficon], eax
7:  test eax, FI_NONE
    jnz 8f
    and eax, 0xffff
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# icon_by_name(ptr, len) -> eax icon from file_icon_names (ignoring case), or -1
icon_by_name:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rip + file_icon_names]
    # rows: length, icon, name
1:  movzx ecx, byte ptr [r13]
    test ecx, ecx
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [r13 + 2]
    call str_ieq
    test eax, eax
    jnz 2f
    movzx eax, byte ptr [r13]
    lea r13, [r13 + rax + 2]
    jmp 1b
2:  movzx eax, byte ptr [r13 + 1]
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# color_by_name(ptr, len) -> eax color, the theme slot past T_ICON (ignoring case), or -1
color_by_name:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  cmp r13d, COLOR_NAMES
    jae 8f
    lea rax, [rip + color_names]
    mov rdx, [rax + r13*8]
    mov rdi, rbx
    mov rsi, r12
    call str_ieq_cstr
    test eax, eax
    jnz 2f
    inc r13d
    jmp 1b
2:  mov eax, r13d
    cmp eax, COLOR_NAMES - 1    # gray
    jne 3f
    mov eax, FI_GREY
3:  EPILOGUE
8:  mov eax, -1
    EPILOGUE

.section .rodata
.p2align 3
# in the order of the theme's icon slots from T_ICON (theme.s, tools/icons.py), then gray for grey
color_names:
    .quad .Lred, .Lorange, .Lyellow, .Lgreen, .Lblue, .Lpurple, .Lpink, .Lcyan, .Lgrey, .Lwhite, .Lgray
.Lred: .asciz "red"
.Lorange: .asciz "orange"
.Lyellow: .asciz "yellow"
.Lgreen: .asciz "green"
.Lblue: .asciz "blue"
.Lpurple: .asciz "purple"
.Lpink: .asciz "pink"
.Lcyan: .asciz "cyan"
.Lgrey: .asciz "grey"
.Lwhite: .asciz "white"
.Lgray: .asciz "gray"
