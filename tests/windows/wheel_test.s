# Wheel messages: 120 a notch scrolls 60 px, and a precision touchpad's smaller steps add up in
# either direction instead of each rounding on its own.
.include "win.inc"
.text
FN main
    PROLOGUE 64
    lea r15, [rip + cases]
1:  mov ebx, [r15]
    test ebx, ebx
    jz 9f
    mov dword ptr [rip + g_scroll_x], 0
    mov dword ptr [rip + g_scroll_y], 0
    mov r12d, [r15 + 8]
2:  xor ecx, ecx
    mov edx, ebx
    mov r8d, [r15 + 4]
    shl r8d, 16                   # the delta is the high word
    xor r9d, r9d
    call win_wndproc
    dec r12d
    jnz 2b
    mov eax, [rip + g_scroll_x]
    cmp eax, [r15 + 12]
    jne 8f
    mov eax, [rip + g_scroll_y]
    cmp eax, [r15 + 16]
    jne 8f
    add r15, 20
    jmp 1b
8:  mov eax, 1
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

.data
.p2align 2
# message, delta, messages sent, then the pixels scrolled across and down
cases:
    .long 0x20a, -120, 4, 0, 240  # notches toward you scroll down
    .long 0x20a, -7, 10, 0, 35
    .long 0x20a, 7, 10, 0, -35
    .long 0x20e, 7, 10, 35, 0     # tilted right
    .long 0x20e, -7, 10, -35, 0
    .long 0x20a, 1, 4, 0, -2
    .long 0
