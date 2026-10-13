# File I/O driver for files.sh: write PATH, load PATH, reload[-binary] PATH REPLACEMENT.
.include "raftaar.inc"
.text
FN main
    PROLOGUE 32
    cmp qword ptr [rip + g_argc], 3
    jb .Lfail
    mov rax, [rip + g_argv]
    mov rcx, [rax + 8]
    mov r12, [rax + 16]
    cmp byte ptr [rcx], 'w'
    je .Lwrite
    cmp byte ptr [rcx], 'a'
    je .Lapp_error
    movzx r14d, byte ptr [rcx]
    call doc_new
    mov rbx, rax
    mov rdi, rax
    mov rsi, r12
    call doc_load
    cmp r14d, 'e'              # error PATH: print the load error, including its errno
    je .Lerror
    test rax, rax
    js .Lfail_doc
    cmp r14d, 'r'
    jne .Ldump
    mov rax, [rbx + DOC_mtime]
    mov [rsp], rax
    mov rax, [rbx + DOC_version]
    mov [rsp + 8], rax
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp + 16], rax
    mov rax, [rbx + DOC_crlf]   # includes DOC_flags
    mov [rsp + 24], rax
    cmp qword ptr [rip + g_argc], 4
    jb .Lfail_doc
    mov rax, [rip + g_argv]
    mov rdi, [rax + 24]
    call file_read_all
    test rax, rax
    jz .Lfail_doc
    mov r13, rax
    mov rdi, r12
    mov rsi, rax
    call file_write_all
    mov r14, rax
    mov rdi, r13
    call mem_free
    test r14, r14
    js .Lfail_doc
    mov rdi, rbx
    call app_reload_doc
    mov rax, [rip + g_argv]
    mov rax, [rax + 8]
    cmp byte ptr [rax + 6], '-' # reject a binary reload, retaining all document state
    je .Lreject_reload
    mov rdi, rbx
    call doc_save
    test rax, rax
    js .Lfail_doc
.Ldump:
    mov rdi, rbx
    call doc_len
    mov r13, rax
    mov rdi, rbx
    call doc_contiguous
    mov edi, 1
    mov rsi, rax
    mov rdx, r13
    call write_all
    mov r12, rax
    mov rdi, rbx
    call doc_free
    mov rax, r12
    jmp .Lresult
.Lreject_reload:
    mov rax, [rsp]
    cmp [rbx + DOC_mtime], rax
    jne .Lfail_doc
    mov rax, [rsp + 8]
    cmp [rbx + DOC_version], rax
    jne .Lfail_doc
    mov rax, [rsp + 16]
    cmp [rbx + DOC_undo + VEC_len], rax
    jne .Lfail_doc
    mov rax, [rsp + 24]
    cmp [rbx + DOC_crlf], rax
    jne .Lfail_doc
    mov rdi, rbx
    call doc_dirty
    test eax, eax
    jnz .Lfail_doc
    jmp .Ldump
.Lwrite:
    mov rdi, r12
    lea rsi, [rip + .Ltext]
    mov edx, 6
    call file_write_all
    jmp .Lresult
.Lapp_error:
    mov rdi, r12
    call app_open_file
    cmp rax, -1
    jne .Lfail
    cmp qword ptr [rip + g_tabs + VEC_len], 0
    jne .Lfail
    xor eax, eax
    EPILOGUE
.Lerror:
    neg rax
    mov rdi, rax
    call log_u64
    call log_nl
    mov rdi, rbx
    call doc_free
    xor eax, eax
.Lresult:
    test rax, rax
    js .Lfail
    xor eax, eax
    EPILOGUE
.Lfail_doc:
    mov rdi, rbx
    call doc_free
.Lfail:
    mov eax, 1
    EPILOGUE
.section .rodata
.Ltext: .ascii "saved\n"
