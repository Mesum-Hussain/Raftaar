# json: recursive-descent parser into an arena (one document at a time)
.include "raftaar.inc"

STRUCT
F JV_type, 4
F JV_n, 4               # elements / pairs / string bytes
F JV_ptr, 8             # string bytes, or child pointers (objects: key,value pairs)
ENDSTRUCT JV_SIZE

.bss
.p2align 3
arena: .quad 0
arena_cap: .quad 0
arena_top: .quad 0
stk: .zero VEC_SIZE             # pending child pointers
jp: .quad 0
jend: .quad 0
jdepth: .long 0
jfail: .long 0

.text

# aalloc(n) -> pointer in the arena (8-byte aligned); grows by chaining new blocks
aalloc:
    add rdi, 7
    and rdi, -8
    mov rax, [rip + arena_top]
    lea rcx, [rax + rdi]
    cmp rcx, [rip + arena_cap]
    ja 1f
    mov [rip + arena_top], rcx
    add rax, [rip + arena]
    ret
1:  # out of space: keep old blocks alive (pointers into them stay valid), start a new one
    push rdi
    push rdi
    mov rax, [rip + arena_cap]
    add rax, rax
    cmp rax, rdi
    jae 2f
    lea rax, [rdi + rdi]
2:  mov ecx, 1 << 20
    cmp rax, rcx
    cmovb rax, rcx
    mov [rip + arena_cap], rax
    mov rdi, rax
    call mem_alloc
    # link the old block for freeing
    mov rcx, [rip + arena]
    mov [rax], rcx
    mov [rip + arena], rax
    mov qword ptr [rip + arena_top], 8
    pop rdi
    pop rdi
    jmp aalloc

# json_reset(): free all blocks but the newest
json_reset:
    push rbx
    mov rax, [rip + arena]
    test rax, rax
    jz 2f
    mov rbx, [rax]
    mov qword ptr [rax], 0
1:  test rbx, rbx
    jz 2f
    mov rdi, rbx
    mov rbx, [rbx]
    call mem_free
    jmp 1b
2:  mov qword ptr [rip + arena_top], 8
    mov qword ptr [rip + stk + VEC_len], 0
    pop rbx
    ret

skip_ws:
    mov rsi, [rip + jp]
    mov rdi, [rip + jend]
1:  cmp rsi, rdi
    jae 2f
    movzx eax, byte ptr [rsi]
    cmp al, ' '
    je 3f
    cmp al, 10
    je 3f
    cmp al, 13
    je 3f
    cmp al, 9
    jne 2f
3:  inc rsi
    jmp 1b
2:  mov [rip + jp], rsi
    ret

# json_parse(ptr, len) -> JV* or 0
FN json_parse
    push rbx
    mov [rip + jp], rdi
    add rdi, rsi
    mov [rip + jend], rdi
    mov dword ptr [rip + jdepth], 0
    mov dword ptr [rip + jfail], 0
    cmp qword ptr [rip + arena], 0
    jne 1f
    mov edi, 8
    call aalloc
1:  call json_reset
    call parse_value
    cmp dword ptr [rip + jfail], 0
    je 2f
    xor eax, eax
2:  pop rbx
    ret

push_child:
    push rbx
    mov rbx, rdi
    lea rdi, [rip + stk]
    mov esi, 8
    call vec_push
    mov [rax], rbx
    pop rbx
    ret

# parse_value() -> JV*
parse_value:
    PROLOGUE
    call skip_ws
    cmp rsi, rdi
    jae .Lpv_fail
    inc dword ptr [rip + jdepth]
    cmp dword ptr [rip + jdepth], 200
    ja .Lpv_fail
    mov edi, JV_SIZE
    call aalloc
    mov rbx, rax
    mov rsi, [rip + jp]
    movzx eax, byte ptr [rsi]
    cmp al, '{'
    je .Lpv_obj
    cmp al, '['
    je .Lpv_arr
    cmp al, '"'
    je .Lpv_str
    cmp al, 't'
    je .Lpv_true
    cmp al, 'f'
    je .Lpv_false
    cmp al, 'n'
    je .Lpv_null
    # number: keep the raw text
    mov dword ptr [rbx + JV_type], JT_NUM
    mov [rbx + JV_ptr], rsi
    mov rdi, [rip + jend]
    mov rcx, rsi
1:  cmp rcx, rdi
    jae 2f
    movzx eax, byte ptr [rcx]
    cmp al, '-'
    je 11f
    cmp al, '+'
    je 11f
    cmp al, '.'
    je 11f
    cmp al, 'e'
    je 11f
    cmp al, 'E'
    je 11f
    sub al, '0'
    cmp al, 9
    ja 2f
11: inc rcx
    jmp 1b
2:  cmp rcx, rsi
    je .Lpv_fail
    mov rax, rcx
    sub rax, rsi
    mov [rbx + JV_n], eax
    mov [rip + jp], rcx
    jmp .Lpv_done
.Lpv_true:
    mov dword ptr [rbx + JV_type], JT_TRUE
    add qword ptr [rip + jp], 4
    jmp .Lpv_done
.Lpv_false:
    mov dword ptr [rbx + JV_type], JT_FALSE
    add qword ptr [rip + jp], 5
    jmp .Lpv_done
.Lpv_null:
    mov dword ptr [rbx + JV_type], JT_NULL
    add qword ptr [rip + jp], 4
    jmp .Lpv_done
.Lpv_str:
    mov dword ptr [rbx + JV_type], JT_STR
    call parse_string
    test rax, rax
    jz .Lpv_fail
    mov [rbx + JV_ptr], rax
    mov [rbx + JV_n], edx
    jmp .Lpv_done
.Lpv_arr:
    mov dword ptr [rbx + JV_type], JT_ARR
    inc qword ptr [rip + jp]
    mov r12, [rip + stk + VEC_len]     # stack base
3:  call skip_ws
    cmp rsi, rdi
    jae .Lpv_fail
    cmp byte ptr [rsi], ']'
    je 5f
    call parse_value
    test rax, rax
    jz .Lpv_fail
    mov rdi, rax
    call push_child
    call skip_ws
    cmp rsi, rdi
    jae .Lpv_fail
    cmp byte ptr [rsi], ','
    jne 3b
    inc qword ptr [rip + jp]
    jmp 3b
5:  inc qword ptr [rip + jp]
    call pop_children
    jmp .Lpv_done
.Lpv_obj:
    mov dword ptr [rbx + JV_type], JT_OBJ
    inc qword ptr [rip + jp]
    mov r12, [rip + stk + VEC_len]
6:  call skip_ws
    cmp rsi, rdi
    jae .Lpv_fail
    cmp byte ptr [rsi], '}'
    je 8f
    cmp byte ptr [rsi], '"'
    jne .Lpv_fail
    call parse_value            # key (string)
    test rax, rax
    jz .Lpv_fail
    mov rdi, rax
    call push_child
    call skip_ws
    cmp rsi, rdi
    jae .Lpv_fail
    cmp byte ptr [rsi], ':'
    jne .Lpv_fail
    inc qword ptr [rip + jp]
    call parse_value
    test rax, rax
    jz .Lpv_fail
    mov rdi, rax
    call push_child
    call skip_ws
    cmp rsi, rdi
    jae .Lpv_fail
    cmp byte ptr [rsi], ','
    jne 6b
    inc qword ptr [rip + jp]
    jmp 6b
8:  inc qword ptr [rip + jp]
    call pop_children
    shr dword ptr [rbx + JV_n], 1
.Lpv_done:
    dec dword ptr [rip + jdepth]
    mov rax, rbx
    EPILOGUE
.Lpv_fail:
    mov dword ptr [rip + jfail], 1
    xor eax, eax
    EPILOGUE

# pop_children(): move stack entries above r12 into the node rbx
pop_children:
    mov rcx, [rip + stk + VEC_len]
    sub rcx, r12
    mov [rbx + JV_n], ecx
    push rcx
    push rcx
    lea rdi, [rcx*8]
    call aalloc
    pop rcx
    pop rcx
    mov [rbx + JV_ptr], rax
    mov rsi, [rip + stk + VEC_ptr]
    lea rsi, [rsi + r12*8]
    mov rdi, rax
    shl rcx, 3
    rep movsb
    mov [rip + stk + VEC_len], r12
    ret

# parse_string() -> rax bytes (arena), rdx length ; jp at the opening quote
parse_string:
    PROLOGUE
    mov rsi, [rip + jp]
    inc rsi
    mov rdi, [rip + jend]
    # length bound: distance to the closing quote
    mov rcx, rsi
1:  cmp rcx, rdi
    jae .Lps_fail
    movzx eax, byte ptr [rcx]
    cmp al, '"'
    je 2f
    cmp al, '\\'
    jne 11f
    inc rcx
11: inc rcx
    jmp 1b
2:  mov r12, rcx                # closing quote
    mov rdi, rcx
    sub rdi, rsi
    inc rdi
    push rsi
    push rsi
    call aalloc
    pop rsi
    pop rsi
    mov r13, rax                # out
    xor r14d, r14d              # out len
.Lps_loop:
    cmp rsi, r12
    jae .Lps_end
    movzx eax, byte ptr [rsi]
    cmp al, '\\'
    je .Lps_esc
    mov [r13 + r14], al
    inc r14
    inc rsi
    jmp .Lps_loop
.Lps_esc:
    movzx eax, byte ptr [rsi + 1]
    add rsi, 2
    mov ecx, 10
    cmp al, 'n'
    je .Lps_put
    mov ecx, 9
    cmp al, 't'
    je .Lps_put
    mov ecx, 13
    cmp al, 'r'
    je .Lps_put
    mov ecx, 8
    cmp al, 'b'
    je .Lps_put
    mov ecx, 12
    cmp al, 'f'
    je .Lps_put
    cmp al, 'u'
    je .Lps_u
    mov ecx, eax                # \" \\ \/ and anything else literally
.Lps_put:
    mov [r13 + r14], cl
    inc r14
    jmp .Lps_loop
.Lps_u:
    mov rdi, rsi
    mov esi, 4
    push rdi
    call parse_hex
    pop rsi
    add rsi, 4
    mov r15d, eax
    # surrogate pair
    lea ecx, [rax - 0xd800]
    cmp ecx, 0x3ff
    ja 3f
    cmp byte ptr [rsi], '\\'
    jne 3f
    cmp byte ptr [rsi + 1], 'u'
    jne 3f
    lea rdi, [rsi + 2]
    push rsi
    mov esi, 4
    call parse_hex
    pop rsi
    lea ecx, [rax - 0xdc00]
    cmp ecx, 0x3ff
    ja 3f
    add rsi, 6
    mov eax, r15d
    sub eax, 0xd800
    shl eax, 10
    add eax, ecx
    add eax, 0x10000
    mov r15d, eax
3:  mov edi, r15d
    push rsi
    lea rsi, [r13 + r14]
    call utf8_encode
    pop rsi
    add r14, rax
    jmp .Lps_loop
.Lps_end:
    lea rax, [r12 + 1]
    mov [rip + jp], rax
    mov byte ptr [r13 + r14], 0
    mov rax, r13
    mov rdx, r14
    EPILOGUE
.Lps_fail:
    xor eax, eax
    EPILOGUE

# json_get(obj, key cstr) -> JV* or 0
FN json_get
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    xor eax, eax
    test rdi, rdi
    jz 9f
    cmp dword ptr [rdi + JV_type], JT_OBJ
    jne 9f
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  cmp r13d, [rbx + JV_n]
    jae 8f
    mov rax, [rbx + JV_ptr]
    mov rcx, r13
    shl rcx, 4
    mov r14, [rax + rcx]
    mov rdi, [r14 + JV_ptr]
    mov esi, [r14 + JV_n]
    mov rdx, r12
    call str_eq_cstr
    test eax, eax
    jnz 2f
    inc r13d
    jmp 1b
2:  mov rax, [rbx + JV_ptr]
    mov rcx, r13
    shl rcx, 4
    mov rax, [rax + rcx + 8]
    jmp 9f
8:  xor eax, eax
9:  add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# json_str(jv) -> rax ptr, rdx len (0,0 unless a string)
FN json_str
    xor eax, eax
    xor edx, edx
    test rdi, rdi
    jz 1f
    cmp dword ptr [rdi + JV_type], JT_STR
    jne 1f
    mov rax, [rdi + JV_ptr]
    mov edx, [rdi + JV_n]
1:  ret

# json_is(jv, cstr) -> 1 if jv is a string equal to cstr
FN json_is
    push rsi
    call json_str
    pop rsi
    test rax, rax
    jz 1f
    mov rdi, rax
    xchg rsi, rdx
    jmp str_eq_cstr
1:  xor eax, eax
    ret

# json_at(arr, i) -> JV* or 0
FN json_at
    xor eax, eax
    test rdi, rdi
    jz 1f
    cmp dword ptr [rdi + JV_type], JT_ARR
    jne 1f
    cmp esi, [rdi + JV_n]
    jae 1f
    mov rax, [rdi + JV_ptr]
    mov rax, [rax + rsi*8]
1:  ret

# json_len(arr) -> element count (0 unless array)
FN json_len
    xor eax, eax
    test rdi, rdi
    jz 1f
    cmp dword ptr [rdi + JV_type], JT_ARR
    jne 1f
    mov eax, [rdi + JV_n]
1:  ret

# json_type(jv) -> JT_* (-1 for null pointer)
FN json_type
    mov eax, -1
    test rdi, rdi
    jz 1f
    mov eax, [rdi + JV_type]
1:  ret
