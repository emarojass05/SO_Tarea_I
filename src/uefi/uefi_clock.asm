; src/uefi/uefi_clock.asm
; --------------------------------------------------------------------
; Modo Reloj: muestra la hora del sistema, ya presente en TimeBuf
; (GetTimeNow la refresca una vez por vuelta del loop principal). Los
; campos de EFI_TIME son binarios, no BCD, asi que PrintDec2 se usa
; directo (no hace falta el PrintBcd que usaba la version BIOS).
; --------------------------------------------------------------------

section .text

DrawClock:
    movzx eax, byte [TimeBuf + TIME_Second]
    cmp   al, [LastSecond]
    je    .skip                 ; ya se dibujo este segundo -> sin parpadeo
    mov   [LastSecond], al

    call  SetCursorRow2
    movzx eax, byte [TimeBuf + TIME_Hour]
    call  PrintDec2
    mov   ax, ':'
    call  PrintChar
    movzx eax, byte [TimeBuf + TIME_Minute]
    call  PrintDec2
    mov   ax, ':'
    call  PrintChar
    movzx eax, byte [TimeBuf + TIME_Second]
    call  PrintDec2
.skip:
    jmp KeyCheck

section .data
LastSecond db -1
