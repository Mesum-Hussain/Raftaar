# compose: dead keys and the Compose (Multi_key) key, using X11 Compose files:
# $XCOMPOSEFILE, else ~/.XCompose, else the locale's file under /usr/share/X11/locale.
# Loaded on the first dead key. Works the same for every platform backend.
.include "raftaar.inc"

.equ CMAX, 8                    # keys per sequence
.equ PARSE_FRAME, 64 + SB_SIZE

STRUCT
F CR_keys, 4*CMAX
F CR_n, 4
F CR_off, 4                     # result in strs
F CR_len, 4
F CR_pad, 4
ENDSTRUCT CR_SIZE

.bss
.p2align 3
rules: .zero VEC_SIZE
strs: .zero SB_SIZE
syspath: .zero SB_SIZE          # the locale's Compose file (%L)
sysdir: .quad 0                 # %S
seq: .zero 4 * CMAX
seq_n: .long 0
loaded: .long 0
depth: .long 0
locbuf: .zero 64

.text

# compose_key(keysym, mods) -> 1 if the key belongs to a compose sequence (swallowed)
FN compose_key
    PROLOGUE
    mov edi, edi
    call canon
    mov ebx, eax
    mov r12d, esi
    test ebx, ebx
    jz .Lck_no
    cmp dword ptr [rip + seq_n], 0
    jne .Lck_more
    # a sequence starts with a dead key or Multi_key, never with a shortcut
    test r12d, MOD_CTRL | MOD_ALT | MOD_SUPER
    jnz .Lck_no
    cmp ebx, 0xff20
    je 1f
    lea eax, [rbx - 0xfe50]
    cmp eax, 0xfe93 - 0xfe50
    ja .Lck_no
1:  cmp dword ptr [rip + loaded], 0
    jne 2f
    call compose_load
2:  mov [rip + seq], ebx
    mov dword ptr [rip + seq_n], 1
    jmp .Lck_match
.Lck_more:
    # modifiers pass through without breaking the sequence
    lea eax, [rbx - 0xffe1]
    cmp eax, 0xffee - 0xffe1
    jbe .Lck_no
    lea eax, [rbx - 0xfe01]
    cmp eax, 0xfe13 - 0xfe01
    jbe .Lck_no
    cmp ebx, 0xff7e             # Mode_switch
    je .Lck_no
    # a shortcut cancels the sequence and runs
    test r12d, MOD_CTRL | MOD_ALT | MOD_SUPER
    jz 3f
    mov dword ptr [rip + seq_n], 0
    jmp .Lck_no
3:  cmp ebx, KEY_ESCAPE
    je .Lck_cancel
    mov eax, [rip + seq_n]
    cmp eax, CMAX
    jae .Lck_cancel
    lea rcx, [rip + seq]
    mov [rcx + rax*4], ebx
    inc dword ptr [rip + seq_n]
.Lck_match:
    call match
    test rax, rax
    jz 4f
    mov rdi, rax
    call emit
    jmp .Lck_yes
4:  test edx, edx
    jnz .Lck_yes                # more keys to come
.Lck_cancel:
    mov dword ptr [rip + seq_n], 0
.Lck_yes:
    mov eax, 1
    EPILOGUE
.Lck_no:
    xor eax, eax
    EPILOGUE

# canon(keysym) -> keysym; Unicode keysyms for Latin-1 become the legacy ones rules use
canon:
    mov eax, edi
    mov ecx, edi
    sub ecx, 0x1000000
    cmp ecx, 0xff
    ja 1f
    mov eax, ecx
1:  ret

# match() -> rax = rule completed by seq (the last one wins) or 0, edx = 1 if longer rules continue it
match:
    push rbx
    push r12
    xor eax, eax
    xor edx, edx
    mov r8, [rip + rules + VEC_ptr]
    mov r9, [rip + rules + VEC_len]
    mov r10d, [rip + seq_n]
    lea r11, [rip + seq]
1:  test r9, r9
    jz 5f
    cmp [r8 + CR_n], r10d
    jb 4f
    xor ecx, ecx
2:  cmp ecx, r10d
    jae 3f
    mov ebx, [r8 + rcx*4]
    cmp ebx, [r11 + rcx*4]
    jne 4f
    inc ecx
    jmp 2b
3:  cmp [r8 + CR_n], r10d
    jne 31f
    mov rax, r8
    jmp 4f
31: mov edx, 1
4:  add r8, CR_SIZE
    dec r9
    jmp 1b
5:  pop r12
    pop rbx
    ret

# emit(rule): type its result
emit:
    PROLOGUE
    mov dword ptr [rip + seq_n], 0
    mov r12d, [rdi + CR_off]
    mov r13d, [rdi + CR_len]
    add r13, r12
1:  cmp r12, r13
    jae 9f
    mov rdi, [rip + strs + SB_ptr]
    add rdi, r12
    mov rsi, r13
    sub rsi, r12
    call utf8_decode
    add r12, rdx
    cmp eax, 0x20
    jb 1b
    mov esi, eax
    mov edi, eax
    cmp eax, 0x7e
    jbe 2f
    or edi, 0x1000000
2:  xor edx, edx
    call app_on_key
    jmp 1b
9:  EPILOGUE

# compose_load(): $XCOMPOSEFILE, else ~/.XCompose, else the system file
compose_load:
    PROLOGUE 16
    mov dword ptr [rip + loaded], 1
    call find_system
    lea rdi, [rip + .Lenv_file]
    call getenv
    test rax, rax
    jz 1f
    mov rdi, rax
    call load_file
    jmp 9f
1:  lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz 2f
    mov rdi, rax
    lea rsi, [rip + .Lxcompose]
    call path_join
    mov rbx, rax
    mov rdi, rax
    call load_file
    mov r12d, eax
    mov rdi, rbx
    call mem_free
    test r12d, r12d
    jnz 9f
2:  mov rdi, [rip + syspath + SB_ptr]
    call load_file
9:  EPILOGUE

# load_file(path) -> 1 if it was read
load_file:
    PROLOGUE
    xor ebx, ebx
    cmp dword ptr [rip + depth], 4
    jae 9f
    call file_read_all
    test rax, rax
    jz 9f
    mov r12, rax
    inc dword ptr [rip + depth]
    mov rdi, rax
    call parse
    dec dword ptr [rip + depth]
    mov rdi, r12
    call mem_free
    mov ebx, 1
9:  mov eax, ebx
    EPILOGUE

# find_system(): syspath = Compose file for the locale, via compose.dir
find_system:
    PROLOGUE 16
    lea rdi, [rip + .Lenv_localedir]
    call getenv
    test rax, rax
    jnz 1f
    lea rax, [rip + .Llocaledir]
1:  mov [rip + sysdir], rax
    call locale_name
    # compose.dir lines: "<file>:<blanks><locale>"
    mov rdi, [rip + sysdir]
    lea rsi, [rip + .Lcomposedir]
    call path_join
    mov rbx, rax
    mov rdi, rax
    call file_read_all
    mov r14, rax
    mov rdi, rbx
    call mem_free
    lea rdi, [rip + syspath]
    call sb_clear
    test r14, r14
    jz .Lfs_default
    mov r12, r14
.Lfs_line:
    cmp byte ptr [r12], 0
    je .Lfs_none
    cmp byte ptr [r12], '#'
    je .Lfs_skip
    mov r13, r12                # file part
2:  movzx eax, byte ptr [r12]
    test eax, eax
    jz .Lfs_none
    cmp al, 10
    je .Lfs_skip
    cmp al, ':'
    je 3f
    inc r12
    jmp 2b
3:  mov [rsp], r12              # end of the file part
    inc r12
4:  cmp byte ptr [r12], ' '
    je 41f
    cmp byte ptr [r12], 9
    jne 5f
41: inc r12
    jmp 4b
5:  # locale part must equal locbuf
    lea rdi, [rip + locbuf]
    xor ecx, ecx
6:  movzx eax, byte ptr [r12 + rcx]
    movzx edx, byte ptr [rdi + rcx]
    test edx, edx
    jz 7f
    cmp eax, edx
    jne .Lfs_skip
    inc rcx
    jmp 6b
7:  cmp al, ' '
    je 8f
    cmp al, 9
    je 8f
    cmp al, 10
    je 8f
    test al, al
    jne .Lfs_skip
8:  lea rdi, [rip + syspath]
    mov rsi, [rip + sysdir]
    call sb_push_cstr
    lea rdi, [rip + syspath]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + syspath]
    mov rsi, r13
    mov rdx, [rsp]
    sub rdx, r13
    call sb_push
    lea rdi, [rip + syspath]
    xor esi, esi
    call sb_push_byte
    mov rdi, r14
    call mem_free
    EPILOGUE
.Lfs_skip:
    movzx eax, byte ptr [r12]
    test eax, eax
    jz .Lfs_none
    inc r12
    cmp al, 10
    jne .Lfs_skip
    jmp .Lfs_line
.Lfs_none:
    mov rdi, r14
    call mem_free
.Lfs_default:
    lea rdi, [rip + syspath]
    mov rsi, [rip + sysdir]
    call sb_push_cstr
    lea rdi, [rip + syspath]
    lea rsi, [rip + .Ldefault_file]
    call sb_push_cstr
    lea rdi, [rip + syspath]
    xor esi, esi
    call sb_push_byte
    EPILOGUE

# locale_name(): locbuf = LC_ALL / LC_CTYPE / LANG with the codeset spelled "UTF-8"
locale_name:
    PROLOGUE
    lea rbx, [rip + .Lenv_locales]
1:  mov rdi, [rbx]
    test rdi, rdi
    jz 3f
    call getenv
    test rax, rax
    jz 2f
    cmp byte ptr [rax], 0
    jne 4f
2:  add rbx, 8
    jmp 1b
3:  lea rax, [rip + .Ldefault_locale]
4:  mov r12, rax
    # C and POSIX have no useful compose table
    mov rdi, rax
    lea rsi, [rip + .Lc]
    call strcmp_eq
    test eax, eax
    jnz 3b
    mov rdi, r12
    lea rsi, [rip + .Lposix]
    call strcmp_eq
    test eax, eax
    jnz 3b
    # copy up to '@', stop the codeset at '.'
    lea rdi, [rip + locbuf]
    xor ecx, ecx
5:  movzx eax, byte ptr [r12 + rcx]
    test al, al
    jz 7f
    cmp al, '@'
    je 7f
    cmp ecx, 40
    jae 7f
    mov [rdi + rcx], al
    inc ecx
    cmp al, '.'
    jne 5b
    # utf8 / utf-8 / UTF-8 -> UTF-8
    lea r13, [r12 + rcx]
    movzx eax, byte ptr [r13]
    or al, 0x20
    cmp al, 'u'
    jne 5b
    mov dword ptr [rdi + rcx], 0x2d465455   # "UTF-"
    mov byte ptr [rdi + rcx + 4], '8'
    add ecx, 5
    jmp 7f
7:  mov byte ptr [rdi + rcx], 0
    EPILOGUE

# parse(text): rules from Compose file text (NUL-terminated)
parse:
    PROLOGUE PARSE_FRAME
    mov r12, rdi
.Lp_line:
    # leading blanks
1:  movzx eax, byte ptr [r12]
    cmp al, ' '
    je 2f
    cmp al, 9
    jne 3f
2:  inc r12
    jmp 1b
3:  test al, al
    jz .Lp_ret
    cmp al, '<'
    je .Lp_rule
    cmp al, 'i'
    jne .Lp_skip
    mov rdi, r12
    mov esi, 7
    lea rdx, [rip + .Linclude]
    mov ecx, 7
    call str_starts
    test eax, eax
    jz .Lp_skip
    add r12, 7
    jmp .Lp_include
.Lp_rule:
    xor r14d, r14d              # keys
    xor r15d, r15d              # bad
.Lp_key:
    cmp byte ptr [r12], '<'
    jne .Lp_colon
    inc r12
    mov rbx, r12
4:  movzx eax, byte ptr [r12]
    test al, al
    jz .Lp_ret
    cmp al, 10
    je .Lp_skip
    cmp al, '>'
    je 5f
    inc r12
    jmp 4b
5:  mov rdi, rbx
    mov rsi, r12
    sub rsi, rbx
    inc r12
    call keysym_value
    mov edi, eax
    call canon
    test eax, eax
    jnz 51f
    mov r15d, 1
51: cmp r14d, CMAX
    jb 52f
    mov r15d, 1
    jmp 53f
52: mov [rsp + 16 + r14*4], eax
    inc r14d
53: movzx eax, byte ptr [r12]
    cmp al, ' '
    je 54f
    cmp al, 9
    jne .Lp_key
54: inc r12
    jmp 53b
.Lp_colon:
    cmp byte ptr [r12], ':'
    jne .Lp_skip
    inc r12
6:  movzx eax, byte ptr [r12]
    cmp al, ' '
    je 61f
    cmp al, 9
    jne 62f
61: inc r12
    jmp 6b
62: mov rax, [rip + strs + SB_len]
    mov [rsp], rax              # result offset
    cmp byte ptr [r12], '"'
    jne .Lp_sym
    inc r12
.Lp_str:
    movzx eax, byte ptr [r12]
    test al, al
    jz .Lp_add
    cmp al, 10
    je .Lp_add
    inc r12
    cmp al, '"'
    je .Lp_add
    cmp al, '\\'
    jne .Lp_byte
    movzx eax, byte ptr [r12]
    test al, al
    jz .Lp_add
    inc r12
    lea ecx, [rax - '0']
    cmp ecx, 7
    ja 7f
    # octal, up to three digits
    mov eax, ecx
    mov edx, 2
71: movzx ecx, byte ptr [r12]
    sub ecx, '0'
    cmp ecx, 7
    ja .Lp_byte
    shl eax, 3
    add eax, ecx
    inc r12
    dec edx
    jnz 71b
    jmp .Lp_byte
7:  cmp al, 'x'
    jne 72f
    mov rdi, r12
    mov esi, 2
    call parse_hex
    add r12, rdx
    jmp .Lp_byte
72: cmp al, 'n'
    jne .Lp_byte
    mov eax, 10
.Lp_byte:
    lea rdi, [rip + strs]
    movzx esi, al
    call sb_push_byte
    jmp .Lp_str
.Lp_sym:
    # result given as a keysym name
    mov rbx, r12
8:  movzx eax, byte ptr [r12]
    cmp al, ' '
    jbe 81f
    cmp al, '#'
    je 81f
    inc r12
    jmp 8b
81: mov rdi, rbx
    mov rsi, r12
    sub rsi, rbx
    jz .Lp_add
    call keysym_value
    mov edi, eax
    call keysym_to_unicode
    test eax, eax
    jz .Lp_add
    lea rdi, [rip + strs]
    mov esi, eax
    call sb_push_utf8
.Lp_add:
    mov rcx, [rip + strs + SB_len]
    sub rcx, [rsp]
    jz 9f
    test r15d, r15d
    jnz 9f
    test r14d, r14d
    jz 9f
    mov [rsp + 8], rcx
    lea rdi, [rip + rules]
    mov esi, CR_SIZE
    call vec_push
    mov [rax + CR_n], r14d
    mov rcx, [rsp]
    mov [rax + CR_off], ecx
    mov rcx, [rsp + 8]
    mov [rax + CR_len], ecx
    xor ecx, ecx
91: cmp ecx, r14d
    jae .Lp_skip
    mov edx, [rsp + 16 + rcx*4]
    mov [rax + rcx*4], edx
    inc ecx
    jmp 91b
9:  mov rax, [rsp]
    mov [rip + strs + SB_len], rax
    jmp .Lp_skip
.Lp_include:
    # include "path" with %L (locale file), %H (home), %S (system dir)
    movzx eax, byte ptr [r12]
    test al, al
    jz .Lp_ret
    cmp al, 10
    je .Lp_skip
    inc r12
    cmp al, '"'
    jne .Lp_include
    lea rbx, [rsp + 64]
    mov qword ptr [rbx + SB_ptr], 0
    mov qword ptr [rbx + SB_len], 0
    mov qword ptr [rbx + SB_cap], 0
10: movzx eax, byte ptr [r12]
    test al, al
    jz 13f
    cmp al, 10
    je 13f
    inc r12
    cmp al, '"'
    je 13f
    cmp al, '%'
    jne 12f
    movzx eax, byte ptr [r12]
    inc r12
    mov rsi, [rip + syspath + SB_ptr]
    cmp al, 'L'
    je 11f
    mov rsi, [rip + sysdir]
    cmp al, 'S'
    je 11f
    cmp al, 'H'
    jne 12f
    lea rdi, [rip + .Lhome]
    call getenv
    mov rsi, rax
    test rsi, rsi
    jz 10b
11: mov rdi, rbx
    call sb_push_cstr
    jmp 10b
12: mov rdi, rbx
    movzx esi, al
    call sb_push_byte
    jmp 10b
13: mov rdi, rbx
    xor esi, esi
    call sb_push_byte
    mov rdi, [rbx + SB_ptr]
    call load_file
    mov rdi, rbx
    call sb_free
.Lp_skip:
    movzx eax, byte ptr [r12]
    test al, al
    jz .Lp_ret
    inc r12
    cmp al, 10
    jne .Lp_skip
    jmp .Lp_line
.Lp_ret:
    EPILOGUE

.section .rodata
.p2align 3
.Lenv_locales: .quad .Llc_all, .Llc_ctype, .Llang, 0
.Llc_all: .asciz "LC_ALL"
.Llc_ctype: .asciz "LC_CTYPE"
.Llang: .asciz "LANG"
.Lc: .asciz "C"
.Lposix: .asciz "POSIX"
.Ldefault_locale: .asciz "en_US.UTF-8"
.Lenv_file: .asciz "XCOMPOSEFILE"
.Lenv_localedir: .asciz "XLOCALEDIR"
.Llocaledir: .asciz "/usr/share/X11/locale"
.Lcomposedir: .asciz "compose.dir"
.Ldefault_file: .asciz "/en_US.UTF-8/Compose"
.Lhome: .asciz "HOME"
.Lxcompose: .asciz ".XCompose"
.Linclude: .ascii "include"
