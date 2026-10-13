# Windows: the system's dark mode (AppsUseLightTheme under the Personalize key, which Settings >
# Personalization > Colors sets for apps), its changes (WM_SETTINGCHANGE), and a title bar that is
# dark with a dark theme (DWMWA_USE_IMMERSIVE_DARK_MODE), as it is on macOS.
.include "win.inc"

.data
title_dark: .long -1            # the title bar's mode as last set

.text

FN win_appearance_init
    PROLOGUE
    call read_dark
    mov [rip + g_sys_dark], eax
    EPILOGUE

# win_setting_changed(): WM_SETTINGCHANGE, sent for the mode ("ImmersiveColorSet") and others
FN win_setting_changed
    PROLOGUE
    call read_dark
    mov edi, eax
    call theme_system_changed
    EPILOGUE

# read_dark() -> eax 1 dark, 0 light, -1 without the value (Windows before 10)
read_dark:
    PROLOGUE 112
    mov dword ptr [rsp + 96], 1
    mov dword ptr [rsp + 100], 4
    mov rcx, 0xffffffff80000001 # HKEY_CURRENT_USER
    lea rdx, [rip + .Lkey]
    lea r8, [rip + .Lvalue]
    mov r9d, 0x10               # RRF_RT_REG_DWORD
    mov qword ptr [rsp + 32], 0
    lea rax, [rsp + 96]
    mov [rsp + 40], rax
    lea rax, [rsp + 100]
    mov [rsp + 48], rax
    API RegGetValueW
    mov ecx, eax
    mov eax, -1
    test ecx, ecx
    jnz 9f
    xor eax, eax
    cmp dword ptr [rsp + 96], 0
    sete al
9:  EPILOGUE

# win_title_theme(hwnd, redraw): the title bar dark or light like the theme. Windows 10 2004 and later
# take attribute 20, earlier builds of 10 attribute 19; a shown window redraws its frame.
FN win_title_theme
    PROLOGUE 112
    mov rbx, rdi
    mov r12d, esi
    mov eax, [rip + g_theme_dark]
    cmp eax, [rip + title_dark]
    je 9f
    mov [rip + title_dark], eax
    mov [rsp + 96], eax
    mov rcx, rbx
    mov edx, 20
    lea r8, [rsp + 96]
    mov r9d, 4
    API DwmSetWindowAttribute
    test eax, eax
    jz 1f
    mov rcx, rbx
    mov edx, 19
    lea r8, [rsp + 96]
    mov r9d, 4
    API DwmSetWindowAttribute
1:  test r12d, r12d
    jz 9f
    mov rcx, rbx
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 40], 0
    mov dword ptr [rsp + 48], 0x37  # SWP_NOSIZE NOMOVE NOZORDER NOACTIVATE FRAMECHANGED
    API SetWindowPos
9:  EPILOGUE

.section .rdata,"dr"
.p2align 1
.Lkey: .short 83, 111, 102, 116, 119, 97, 114, 101, 92, 77, 105, 99, 114, 111, 115, 111, 102, 116, 92, 87, 105, 110, 100, 111, 119, 115, 92, 67, 117, 114, 114, 101, 110, 116, 86, 101, 114, 115, 105, 111, 110, 92, 84, 104, 101, 109, 101, 115, 92, 80, 101, 114, 115, 111, 110, 97, 108, 105, 122, 101, 0  # Software\Microsoft\Windows\CurrentVersion\Themes\Personalize
.Lvalue: .short 65, 112, 112, 115, 85, 115, 101, 76, 105, 103, 104, 116, 84, 104, 101, 109, 101, 0  # AppsUseLightTheme
