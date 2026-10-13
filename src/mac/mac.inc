// raftaar on macOS: macros for the native AArch64 code
//
// The rest of raftaar is x86-64 assembly that tools/arm64.py translates. Translated functions take
// arguments in x0-x5 (rdi rsi rdx rcx r8 r9), return in x8 (rax), keep x19-x24 and x28 like AAPCS,
// and expect their return address on the x86 stack, x28. XCALL makes such a call; XRET returns
// to translated code from a native function it called.

.macro XCALL fn
    adr x17, Lxc\@
    str x17, [x28, #-8]!
    bl \fn
Lxc\@:
.endm

.macro XRET
    add x28, x28, #8
    ret
.endm

// AAPCS frame with x19-x28 saved; \size bytes of locals at [sp]
.macro ENTER size=0
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]
    .if \size
    sub sp, sp, #\size
    .endif
.endm

.macro LEAVE
    mov sp, x29
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x23, x24, [sp, #48]
    ldp x25, x26, [sp, #64]
    ldp x27, x28, [sp, #80]
    ldp x29, x30, [sp], #96
.endm

// address of a symbol
.macro ADR reg, sym
    adrp \reg, \sym@PAGE
    add \reg, \reg, \sym@PAGEOFF
.endm

.macro FN name
    .text
    .globl \name
    .p2align 2
\name:
.endm
