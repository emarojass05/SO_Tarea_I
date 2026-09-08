; src/uefi/uefi_defs.inc
; --------------------------------------------------------------------
; Offsets into the standard UEFI tables/protocols (UEFI Spec 2.x, x64).
; These layouts are part of the UEFI ABI: identical on every compliant
; x86_64 firmware, so hardcoding them here (instead of pulling in the
; EDK2 C headers) is safe and keeps this project 100% ensamblador -
; no C toolchain involved anywhere.
;
; Calling convention: Microsoft x64 (the one UEFI mandates on x86_64).
;   args 1-4 -> RCX, RDX, R8, R9 ; caller reserves 0x20 "shadow space"
;   on the stack before every call ; RSP must be 16-byte aligned at the
;   instant the CALL executes. See the EFI_PROLOGUE/EFI_EPILOGUE macros
;   below - every routine that calls into firmware uses them.
; --------------------------------------------------------------------

; ---- EFI_SYSTEM_TABLE (offsets from the pointer handed to efi_main in RDX)
%define ST_ConIn            0x30
%define ST_ConOut           0x40
%define ST_RuntimeServices  0x58
%define ST_BootServices     0x60

; ---- EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL (*ConOut)
%define TXTOUT_OutputString      0x08
%define TXTOUT_SetAttribute      0x28
%define TXTOUT_ClearScreen       0x30
%define TXTOUT_SetCursorPosition 0x38
%define TXTOUT_EnableCursor      0x40

; ---- EFI_SIMPLE_TEXT_INPUT_PROTOCOL (*ConIn)
%define TXTIN_ReadKeyStroke  0x08
%define TXTIN_WaitForKey     0x10   ; EFI_EVENT handle (not a function)

; ---- EFI_RUNTIME_SERVICES
%define RT_GetTime           0x18

; ---- EFI_BOOT_SERVICES
%define BS_WaitForEvent      0x60
%define BS_Stall             0xF8

; ---- EFI_INPUT_KEY (filled in by ReadKeyStroke)
%define KEY_ScanCode         0x00   ; UINT16
%define KEY_UnicodeChar      0x02   ; CHAR16

; ESC is a "scan coded" key per the UEFI spec: most firmwares report it as
; ScanCode=SCAN_ESC with UnicodeChar=0 (NOT UnicodeChar=0x1B like BIOS's
; int 0x16 does) - KeyCheck checks both to be safe across firmware.
%define SCAN_ESC             0x17

; ---- EFI_TIME (filled in by GetTime) - all fields BINARY, not BCD
%define TIME_Year            0x00   ; UINT16
%define TIME_Month           0x02   ; UINT8
%define TIME_Day             0x03   ; UINT8
%define TIME_Hour            0x04   ; UINT8  0-23
%define TIME_Minute          0x05   ; UINT8  0-59
%define TIME_Second          0x06   ; UINT8  0-59
%define TIME_Nanosecond      0x08   ; UINT32
%define EFI_TIME_SIZE        16

%define EFI_SUCCESS          0
%define EFI_NOT_READY_LOW32  0x0000000E   ; low 32 bits of EFI_NOT_READY (high bit set = error, masked off in the 32-bit compare we use)

; Standard text attributes (Foreground | Background<<4 - same byte layout
; the old VGA attribute byte used, which is why the flash colours below
; reuse the exact values alarm.asm already had).
%define EFI_WHITE_ON_BLUE    0x1F
%define EFI_WHITE_ON_RED     0x4F
%define EFI_LIGHTGRAY        0x07

; Stack-alignment prologue/epilogue for any routine that calls a UEFI
; table/protocol function. UEFI x64 requires RSP % 16 == 0 at the CALL
; instruction plus a 0x20-byte shadow space for the callee to spill its
; register args into. Forcing alignment with `and rsp,-16` after saving
; the real RSP in RBP means callers of OUR routines don't need to worry
; about what alignment they call us at.
%macro EFI_PROLOGUE 0
    push rbp
    mov  rbp, rsp
    and  rsp, -16
    sub  rsp, 0x20
%endmacro

%macro EFI_EPILOGUE 0
    mov  rsp, rbp
    pop  rbp
%endmacro
