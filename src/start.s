.include "raftaar.inc"

FN _start
    mov rdi, rsp
    and rsp, -16
    call sys_init
    call main
    mov edi, eax
    jmp sys_exit
