; src/uefi/uefi_main.asm
; --------------------------------------------------------------------
; Punto de entrada UEFI (reemplaza boot.asm + app.asm de la version
; legacy). No hace falta un "stage 1" que lea sectores de disco a mano:
; el propio firmware localiza \EFI\BOOT\BOOTX64.EFI en la particion
; FAT del medio de arranque, lo carga en memoria y salta directo a
; efi_main con el ABI x64 de Microsoft (que es el que exige UEFI):
;   RCX = ImageHandle, RDX = puntero a EFI_SYSTEM_TABLE.
; Todo lo especifico de cada modo sigue en su propio modulo (mismo
; criterio de "Makefiles y modularidad" que ya usaba la version BIOS):
;   uefi_video.asm     - pantalla/teclado (protocolos UEFI)
;   uefi_time.asm       - GetTime() (RTC real via Runtime Services)
;   uefi_clock.asm      - Modo Reloj
;   uefi_stopwatch.asm  - Modo Cronometro
;   uefi_alarm.asm      - UI de alarma + deteccion de coincidencia
; --------------------------------------------------------------------

bits 64
default rel

%include "uefi_defs.inc"

section .text
global efi_main

efi_main:
    mov  rax, [rdx + ST_ConIn]
    mov  [gConIn], rax
    mov  rax, [rdx + ST_ConOut]
    mov  [gConOut], rax
    mov  rax, [rdx + ST_RuntimeServices]
    mov  [gRT], rax
    mov  rax, [rdx + ST_BootServices]
    mov  [gBS], rax

    mov  byte [Mode], 0

    lea  rsi, [rel ConfirmMsg]
    call PrintString
    call ReadKeyBlocking       ; bloquea hasta que se presione cualquier tecla

    call ShowTitle

MainLoop:
    call GetTimeNow             ; TimeBuf <- hora actual (RTC real via GetTime)
    call CheckAlarmMatch        ; activa AlarmTriggered si HH:MM coincide

    cmp  byte [AlarmTriggered], 0
    jne  AlarmRing

    cmp  byte [Mode], 0
    je   DrawClock
    jmp  DrawStopwatch

KeyCheck:
    call ReadKeyPoll
    jnc  .noKey
    cmp  word [EfiKeyBuf + KEY_ScanCode], SCAN_ESC
    je   Finish                 ; ESC (scan code) -> finalizar
    movzx eax, word [EfiKeyBuf + KEY_UnicodeChar]
    cmp  al, 0x1b               ; ESC (algunos firmwares tambien mandan esto)
    je   Finish
    cmp  al, 'm'
    je   SwitchMode
    cmp  al, 'M'
    je   SwitchMode
    cmp  al, 'a'
    je   DoSetAlarm
    cmp  al, 'A'
    je   DoSetAlarm
    cmp  al, 'c'
    je   DoCancelAlarm
    cmp  al, 'C'
    je   DoCancelAlarm
    cmp  byte [Mode], 0
    je   .noKey                 ; S/R solo aplican en Modo Cronometro
    cmp  al, 's'
    je   DoToggle
    cmp  al, 'S'
    je   DoToggle
    cmp  al, 'r'
    je   DoReset
    cmp  al, 'R'
    je   DoReset
.noKey:
    mov  ecx, 80000             ; ~80ms entre sondeos: responsivo, sin acaparar CPU
    call StallUs
    jmp  MainLoop

SwitchMode:
    xor  byte [Mode], 1
    mov  byte [LastSecond], -1
    mov  dword [LastSwSecs], -1
    call ShowTitle
    jmp  MainLoop

DoToggle:
    call ToggleStopwatch
    jmp  MainLoop

DoReset:
    mov  dword [SwElapsedSecs], 0
    mov  byte  [SwRunning], 0
    mov  dword [LastSwSecs], -1
    jmp  MainLoop

DoSetAlarm:
    call SetAlarmPrompt
    jmp  MainLoop

DoCancelAlarm:
    mov  byte [AlarmSet], 0
    mov  byte [AlarmTriggered], 0
    call ShowTitle
    jmp  MainLoop

Finish:
    call ClearScreen
    call ShowCursor             ; deja el cursor como lo encontramos
    lea  rsi, [rel ExitMsg]
    call PrintString
.hang:
    hlt
    jmp .hang

ShowTitle:
    call ClearScreen
    call HideCursor
    cmp  byte [Mode], 0
    je   .clockTitle
    lea  rsi, [rel SwTitle]
    call PrintString
    call PrintAlarmStatus
    ret
.clockTitle:
    lea  rsi, [rel ClockTitle]
    call PrintString
    call PrintAlarmStatus
    ret

; --------------------------------------------------------------------
; Estado global / tablas UEFI resueltas una vez en efi_main
; --------------------------------------------------------------------
section .data
Mode      db 0                  ; 0 = Reloj, 1 = Cronometro

gConIn    dq 0
gConOut   dq 0
gRT       dq 0
gBS       dq 0
gWaitEvt  dq 0
gWaitIdx  dq 0

EfiKeyBuf: dw 0, 0               ; ScanCode, UnicodeChar (EFI_INPUT_KEY)

ConfirmMsg dw __utf16__(`Presione una tecla para continuar...\r\n`), 0
ClockTitle dw __utf16__(`Modo Reloj  (A: alarma, C: cancelar, M: modo, ESC: salir)\r\n`), 0
SwTitle    dw __utf16__(`Modo Cronometro (S: iniciar/pausar, R: reset, A: alarma, M: modo, ESC: salir)\r\n`), 0
ExitMsg    dw __utf16__(`\r\nPrograma finalizado.`), 0

; --------------------------------------------------------------------
; Modulos (ver rubrica "Makefiles y modularidad")
; --------------------------------------------------------------------
%include "uefi_video.asm"
%include "uefi_time.asm"
%include "uefi_clock.asm"
%include "uefi_stopwatch.asm"
%include "uefi_alarm.asm"
