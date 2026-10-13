# GIF: the first frame, with its transparency and interlacing, on the logical screen
.include "raftaar.inc"

.bss
.p2align 3
img: .quad 0
end: .quad 0
data: .zero SB_SIZE             # the frame's LZW data, sub-blocks joined
idx: .quad 0                    # color index per frame pixel
.p2align 2
pal: .zero 4 * 256
prefix: .zero 2 * 4096
suffix: .zero 4096
first: .zero 4096
length: .zero 2 * 4096
trans: .long 0                  # transparent index, -1 without one
fx: .long 0                     # frame rectangle
fy: .long 0
fw: .long 0
fh: .long 0
interlaced: .long 0
mincode: .long 0

.text

# gif_decode(ptr, len, IMG*) -> 0 or -1
FN gif_decode
    PROLOGUE 32
    mov [rip + img], rdx
    lea rax, [rdi + rsi]
    mov [rip + end], rax
    mov r12, rdi
    mov qword ptr [rip + idx], 0
    lea rdi, [rip + data]
    call sb_clear
    mov dword ptr [rip + trans], -1
    cmp rsi, 13
    jb .Lfail
    movzx eax, word ptr [r12 + 6]
    mov [rsp], eax              # screen w
    movzx eax, word ptr [r12 + 8]
    mov [rsp + 4], eax          # screen h
    movzx ebx, byte ptr [r12 + 10]
    lea r13, [r12 + 13]
    # a gray ramp stands in for a missing color table
    lea rdi, [rip + pal]
    xor ecx, ecx
1:  mov eax, ecx
    imul eax, eax, 0x010101
    or eax, 0xff000000
    mov [rdi + rcx*4], eax
    inc ecx
    cmp ecx, 256
    jb 1b
    test ebx, 0x80
    jz .Lblock
    mov rdi, r13
    mov esi, ebx
    call read_table
    test rax, rax
    jz .Lfail
    mov r13, rax
.Lblock:
    lea rax, [r13 + 1]
    cmp rax, [rip + end]
    ja .Lfail
    movzx eax, byte ptr [r13]
    cmp eax, 0x21
    je .Lext
    cmp eax, 0x2c
    je .Limage
    jmp .Lfail                  # the trailer or garbage before any image
.Lext:
    lea rax, [r13 + 2]
    cmp rax, [rip + end]
    ja .Lfail
    movzx ebx, byte ptr [r13 + 1]
    add r13, 2
    # graphic control: the transparent index
    cmp ebx, 0xf9
    jne 1f
    lea rax, [r13 + 5]
    cmp rax, [rip + end]
    ja 1f
    cmp byte ptr [r13], 4
    jne 1f
    test byte ptr [r13 + 1], 1
    jz 1f
    movzx eax, byte ptr [r13 + 4]
    mov [rip + trans], eax
1:  mov rdi, r13
    xor esi, esi
    call sub_blocks
    test rax, rax
    jz .Lfail
    mov r13, rax
    jmp .Lblock
.Limage:
    lea rax, [r13 + 11]
    cmp rax, [rip + end]
    ja .Lfail
    movzx eax, word ptr [r13 + 1]
    mov [rip + fx], eax
    movzx eax, word ptr [r13 + 3]
    mov [rip + fy], eax
    movzx eax, word ptr [r13 + 5]
    mov [rip + fw], eax
    movzx eax, word ptr [r13 + 7]
    mov [rip + fh], eax
    movzx ebx, byte ptr [r13 + 9]
    mov eax, ebx
    shr eax, 6
    and eax, 1
    mov [rip + interlaced], eax
    add r13, 10
    test ebx, 0x80
    jz 1f
    mov rdi, r13
    mov esi, ebx
    call read_table
    test rax, rax
    jz .Lfail
    mov r13, rax
1:  lea rax, [r13 + 1]
    cmp rax, [rip + end]
    ja .Lfail
    movzx eax, byte ptr [r13]
    lea ecx, [rax - 1]
    cmp ecx, 10
    ja .Lfail
    mov [rip + mincode], eax
    lea rdi, [r13 + 1]
    lea rsi, [rip + data]
    call sub_blocks
    # a screen of no size takes the frame's
    mov eax, [rsp]
    test eax, eax
    jz 2f
    mov eax, [rsp + 4]
    test eax, eax
    jnz 3f
2:  mov eax, [rip + fx]
    add eax, [rip + fw]
    mov [rsp], eax
    mov eax, [rip + fy]
    add eax, [rip + fh]
    mov [rsp + 4], eax
3:  mov rdi, [rip + img]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    call img_alloc
    test rax, rax
    jz .Lfail
    # indices, then colors onto the screen; a frame, which may reach past the screen, within the
    # limits of an image too (its 16-bit sides alone ask for up to 4 GiB of indices)
    mov eax, [rip + fw]
    mov ecx, [rip + fh]
    imul rax, rcx
    test rax, rax
    jz .Lok
    cmp rax, IMG_MAXPX
    ja .Lbig
    mov r14d, eax
    lea rdi, [rax + 16]
    call mem_alloc_try
    test rax, rax
    jz .Lfail
    mov [rip + idx], rax
    mov edi, r14d
    call lzw
    mov r15d, eax               # pixels decoded
    call paint
.Lok:
    call cleanup
    xor eax, eax
    EPILOGUE
.Lbig:
    lea rax, [rip + .Lerr_frame]
    mov [rip + g_img_err], rax
.Lfail:
    call cleanup
    mov eax, -1
    EPILOGUE

cleanup:
    push rbx
    mov rdi, [rip + idx]
    call mem_free
    mov qword ptr [rip + idx], 0
    lea rdi, [rip + data]
    call sb_free
    pop rbx
    ret

# read_table(ptr, flags) -> after the color table (into pal), 0 when the data ends first
read_table:
    mov ecx, esi
    and ecx, 7
    mov eax, 2
    shl eax, cl                 # entries
    lea edx, [rax + rax*2]
    lea r8, [rdi + rdx]
    cmp r8, [rip + end]
    ja 9f
    lea r9, [rip + pal]
    xor ecx, ecx
1:  cmp ecx, eax
    jae 2f
    movzx edx, byte ptr [rdi]
    shl edx, 16
    mov dh, [rdi + 1]
    mov dl, [rdi + 2]
    or edx, 0xff000000
    mov [r9 + rcx*4], edx
    add rdi, 3
    inc ecx
    jmp 1b
2:  # the rest black
    cmp ecx, 256
    jae 3f
    mov dword ptr [r9 + rcx*4], 0xff000000
    inc ecx
    jmp 2b
3:  mov rax, r8
    ret
9:  xor eax, eax
    ret

# sub_blocks(ptr, sb or 0) -> after the terminating empty block, 0 if the data ends first; appends the bytes to sb
sub_blocks:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
1:  cmp rbx, [rip + end]
    jae 8f
    movzx r13d, byte ptr [rbx]
    inc rbx
    test r13d, r13d
    jz 9f
    mov rax, [rip + end]
    sub rax, rbx
    cmp r13, rax
    jbe 2f
    mov r13, rax                # cut short: take what is there
2:  test r12, r12
    jz 3f
    mov rdi, r12
    mov rsi, rbx
    mov rdx, r13
    call sb_push
3:  add rbx, r13
    jmp 1b
8:  xor ebx, ebx
9:  mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret

# lzw(pixels) -> indices decoded into idx (fewer when the data is short or broken)
lzw:
    PROLOGUE 32
    mov [rsp], edi              # capacity
    mov r12, [rip + data + SB_ptr]
    mov r13, [rip + data + SB_len]
    add r13, r12                # end
    xor r14d, r14d              # bit buffer
    xor r15d, r15d              # its bits
    xor ebx, ebx                # output position
    # roots
    mov ecx, [rip + mincode]
    mov eax, 1
    shl eax, cl
    mov [rsp + 4], eax          # clear
    xor ecx, ecx
    lea r8, [rip + suffix]
    lea r9, [rip + first]
    lea r10, [rip + length]
    lea r11, [rip + prefix]
1:  cmp ecx, [rsp + 4]
    jae 2f
    mov [r8 + rcx], cl
    mov [r9 + rcx], cl
    mov word ptr [r10 + rcx*2], 1
    mov word ptr [r11 + rcx*2], 0xffff
    inc ecx
    jmp 1b
2:  call .Lclear
.Lcode:
    # next code, LSB first
    mov ecx, [rsp + 12]         # code size
3:  cmp r15d, ecx
    jae 4f
    cmp r12, r13
    jae .Ldone
    movzx eax, byte ptr [r12]
    inc r12
    xchg ecx, r15d
    shl rax, cl
    xchg ecx, r15d
    or r14, rax
    add r15d, 8
    jmp 3b
4:  mov eax, 1
    shl eax, cl
    dec eax
    and eax, r14d               # code
    shr r14, cl
    sub r15d, ecx
    mov edx, [rsp + 4]
    cmp eax, edx
    je 21f
    inc edx
    cmp eax, edx
    je .Ldone                   # end of information
    mov ecx, [rsp + 16]         # previous code
    test ecx, ecx
    js 6f
    mov edx, [rsp + 8]          # next free code
    cmp eax, edx
    ja .Ldone                   # not yet defined
    je 5f
    # known code: add previous + its first byte
    cmp edx, 4096
    jae 6f
    lea r8, [rip + first]
    movzx r9d, byte ptr [r8 + rax]
    call .Ladd
    jmp 6f
5:  # the code being defined: previous + previous's first byte
    cmp edx, 4096
    jae .Ldone
    lea r8, [rip + first]
    movzx r9d, byte ptr [r8 + rcx]
    call .Ladd
6:  mov [rsp + 16], eax
    call .Lemit
    cmp ebx, [rsp]
    jae .Ldone
    jmp .Lcode
21: call .Lclear
    jmp .Lcode
.Ldone:
    mov eax, ebx
    EPILOGUE
# reset the table
.Lclear:
    mov ecx, [rip + mincode]
    inc ecx
    mov [rsp + 8 + 12], ecx     # code size (our frame is 8 lower inside the call)
    mov eax, [rsp + 8 + 4]
    add eax, 2
    mov [rsp + 8 + 8], eax      # next free code
    mov dword ptr [rsp + 8 + 16], -1
    ret
# add the entry (previous code ecx, byte r9d) at the next free code; the code size grows when it fills
.Ladd:
    push rax
    mov edx, [rsp + 16 + 8]
    lea r8, [rip + prefix]
    mov [r8 + rdx*2], cx
    lea r8, [rip + suffix]
    mov [r8 + rdx], r9b
    lea r8, [rip + first]
    movzx r10d, byte ptr [r8 + rcx]
    mov [r8 + rdx], r10b
    lea r8, [rip + length]
    movzx r10d, word ptr [r8 + rcx*2]
    inc r10d
    mov [r8 + rdx*2], r10w
    inc edx
    mov [rsp + 16 + 8], edx
    mov ecx, [rsp + 16 + 12]
    mov eax, 1
    shl eax, cl
    cmp edx, eax
    jb 1f
    cmp ecx, 12
    jae 1f
    inc dword ptr [rsp + 16 + 12]
1:  pop rax
    ret
# write the string of code eax at the output position, backwards from its end
.Lemit:
    lea r8, [rip + length]
    movzx ecx, word ptr [r8 + rax*2]
    lea edx, [rbx + rcx - 1]    # position of its last byte
    add ebx, ecx
    mov r9, [rip + idx]
    lea r10, [rip + suffix]
    lea r11, [rip + prefix]
1:  test ecx, ecx
    jz 3f
    cmp edx, [rsp + 8]
    jae 2f
    movzx r8d, byte ptr [r10 + rax]
    mov [r9 + rdx], r8b
2:  movzx eax, word ptr [r11 + rax*2]
    dec edx
    dec ecx
    cmp eax, 0xffff
    jne 1b
3:  ret

# paint(): r15d decoded indices onto the screen, deinterlacing
paint:
    PROLOGUE 16
    mov rbx, [rip + img]
    mov r12, [rip + idx]
    xor r13d, r13d              # frame row, in decoding order
    xor r14d, r14d              # index position
1:  cmp r13d, [rip + fh]
    jae 9f
    mov eax, r14d
    add eax, [rip + fw]
    cmp eax, r15d
    ja 9f                       # rows not decoded stay transparent
    # the row it belongs to
    mov eax, r13d
    cmp dword ptr [rip + interlaced], 0
    je 2f
    mov edi, r13d
    call interlace_row
2:  add eax, [rip + fy]
    cmp eax, [rbx + IMG_h]
    jae 8f
    imul eax, [rbx + IMG_w]
    mov rdi, [rbx + IMG_px]
    lea rdi, [rdi + rax*4]
    lea rsi, [rip + pal]
    xor ecx, ecx
3:  cmp ecx, [rip + fw]
    jae 8f
    mov edx, ecx
    add edx, [rip + fx]
    cmp edx, [rbx + IMG_w]
    jae 8f
    lea eax, [r14 + rcx]
    movzx eax, byte ptr [r12 + rax]
    cmp eax, [rip + trans]
    je 4f
    mov eax, [rsi + rax*4]
    mov [rdi + rdx*4], eax
4:  inc ecx
    jmp 3b
8:  add r14d, [rip + fw]
    inc r13d
    jmp 1b
9:  EPILOGUE

# interlace_row(n) -> eax row of the n-th decoded row: every 8th from 0, every 8th from 4, every 4th from 2, every 2nd from 1
interlace_row:
    mov eax, [rip + fh]
    add eax, 7
    shr eax, 3                  # rows in pass 1
    cmp edi, eax
    jae 1f
    lea eax, [rdi*8]
    ret
1:  sub edi, eax
    mov eax, [rip + fh]
    add eax, 3
    shr eax, 3                  # pass 2
    cmp edi, eax
    jae 2f
    lea eax, [rdi*8 + 4]
    ret
2:  sub edi, eax
    mov eax, [rip + fh]
    add eax, 1
    shr eax, 2                  # pass 3
    cmp edi, eax
    jae 3f
    lea eax, [rdi*4 + 2]
    ret
3:  sub edi, eax
    lea eax, [rdi*2 + 1]
    ret

.section .rodata
.Lerr_frame: .asciz "The image is too large to show"
