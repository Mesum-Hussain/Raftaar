# Native thread-local keyboard state: Right Alt is a shortcut, Ctrl+Right Alt is AltGr.
.include "win.inc"
.text
FN main
    PROLOGUE 608
    lea rcx, [rsp + 96]
    API GetKeyboardState
    test eax, eax
    jz 8f
    lea rdi, [rsp + 352]
    xor esi, esi
    mov edx, 256
    call memset
    mov byte ptr [rsp + 352 + 18], 128
    mov byte ptr [rsp + 352 + 0xa5], 128
    lea rcx, [rsp + 352]
    API SetKeyboardState
    test eax, eax
    jz 7f
    call win_mods
    cmp eax, MOD_ALT
    jne 7f
    mov byte ptr [rsp + 352 + 17], 128
    lea rcx, [rsp + 352]
    API SetKeyboardState
    test eax, eax
    jz 7f
    call win_mods
    test eax, eax
    jnz 7f
    mov byte ptr [rsp + 352 + 16], 128
    lea rcx, [rsp + 352]
    API SetKeyboardState
    test eax, eax
    jz 7f
    call win_mods
    cmp eax, MOD_SHIFT
    jne 7f
    xor ebx, ebx
    jmp 9f
7:  mov ebx, 1
9:  lea rcx, [rsp + 96]
    API SetKeyboardState
    mov eax, ebx
    EPILOGUE
8:  mov eax, 1
    EPILOGUE
