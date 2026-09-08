; src/uefi/uefi_time.asm
; --------------------------------------------------------------------
; Fuente de tiempo real de hardware bajo UEFI: EFI_RUNTIME_SERVICES->
; GetTime(). Es el equivalente NATIVO de UEFI a la interrupcion BIOS
; int 0x1A/AH=02h que usa la version legacy - ambas leen el mismo chip
; RTC de la placa; la diferencia es que un ejecutable UEFI x64 no puede
; ejecutar interrupciones de BIOS en absoluto (no hay modo real activo),
; asi que GetTime() es la unica via valida bajo esta arquitectura. A
; diferencia de int 1Ah (que regresa BCD), EFI_TIME ya viene en binario,
; asi que no hace falta PrintBcd/empaquetado BCD en ningun lado.
; --------------------------------------------------------------------

section .text

; Refresca TimeBuf con la hora actual. Se llama una vez por vuelta del
; loop principal; tanto DrawClock como CheckAlarmMatch y el cronometro
; reusan ese mismo TimeBuf en vez de pedir la hora varias veces.
GetTimeNow:
    EFI_PROLOGUE
    lea  rcx, [rel TimeBuf]
    xor  rdx, rdx           ; Capabilities = NULL (no lo necesitamos)
    mov  rax, [gRT]
    call qword [rax + RT_GetTime]
    EFI_EPILOGUE

    ; El RTC de este equipo guarda la hora en UTC, no en hora local.
    ; Costa Rica es siempre UTC-6 (no tiene horario de verano), asi
    ; que se ajusta aqui una sola vez -sobre TimeBuf- para que el
    ; reloj, el cronometro y la comparacion de la alarma usen todos
    ; la hora local correcta sin duplicar el ajuste en cada modulo.
    movzx eax, byte [TimeBuf + TIME_Hour]
    sub   eax, 6
    jns   .noWrap
    add   eax, 24
.noWrap:
    mov   [TimeBuf + TIME_Hour], al
    ret

section .data
TimeBuf: times EFI_TIME_SIZE db 0
