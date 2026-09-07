; src/app/app.asm
; --------------------------------------------------------------------
; Entry point, main loop and key dispatch. Everything mode-specific
; lives in its own module (see the %include list at the bottom):
;   clock.asm      - Modo Reloj
;   stopwatch.asm  - Modo Cronometro
;   alarm.asm      - alarm UI (set/ring)
;   rtc_alarm.asm  - hardware RTC alarm interrupt (IRQ8/INT 70h)
;   video.asm      - shared screen/keyboard helpers
; --------------------------------------------------------------------

bits 16
org 0x8000

AppStart:
    mov si, ConfirmMsg
    call PrintString

    xor ah, ah
    int 0x16                 ; Block until a key is pressed

    call InstallRtcVector     ; hook the RTC's own alarm interrupt (IRQ8/INT 70h)
    call ShowTitle

MainLoop:
    ; AlarmTriggered is set directly by RtcAlarmISR (rtc_alarm.asm), fired
    ; by the RTC chip's own hardware alarm interrupt - no need to poll
    ; INT 1Ah here anymore.
    cmp byte [AlarmTriggered], 0
    jne AlarmRing

    cmp byte [Mode], 0
    je DrawClock
    jmp DrawStopwatch

KeyCheck:
    mov ah, 0x01
    int 0x16
    jz MainLoop
    xor ah, ah
    int 0x16
    cmp al, 0x1b              ; ESC -> finish
    je Finish
    cmp al, 'm'
    je SwitchMode
    cmp al, 'M'
    je SwitchMode
    cmp al, 'a'
    je DoSetAlarm
    cmp al, 'A'
    je DoSetAlarm
    cmp al, 'c'
    je DoCancelAlarm
    cmp al, 'C'
    je DoCancelAlarm
    cmp byte [Mode], 0
    je MainLoop               ; S/R only apply in Stopwatch Mode
    cmp al, 's'
    je DoToggle
    cmp al, 'S'
    je DoToggle
    cmp al, 'r'
    je DoReset
    cmp al, 'R'
    je DoReset
    jmp MainLoop

SwitchMode:
    xor byte [Mode], 1
    call ShowTitle
    jmp MainLoop

DoToggle:
    call ToggleStopwatch32
    jmp MainLoop

DoReset:
    mov word [SwElapsedLo], 0
    mov word [SwElapsedHi], 0
    mov byte [SwRunning], 0
    jmp MainLoop

DoSetAlarm:
    call SetAlarmPrompt
    jmp MainLoop

DoCancelAlarm:
    call DisableRtcAlarmInterrupt
    mov byte [AlarmSet], 0
    mov byte [AlarmTriggered], 0
    call ShowTitle
    jmp MainLoop

Finish:
    call DisableRtcAlarmInterrupt
    call RestoreRtcVector
    call ClearScreen
    call ShowCursor           ; leave the cursor as we found it (HideCursor hid it in ShowTitle)
    mov si, ExitMsg
    call PrintString
.Hang:
    hlt
    jmp .Hang

ShowTitle:
    call ClearScreen
    call HideCursor
    cmp byte [Mode], 0
    je .C
    mov si, SwTitle
    call PrintString
    call PrintAlarmStatus
    ret
.C:
    mov si, ClockTitle
    call PrintString
    call PrintAlarmStatus
    ret

; --------------------------------------------------------------------
; State
; --------------------------------------------------------------------
Mode db 0          ; 0 = Clock, 1 = Stopwatch

ConfirmMsg db 'Presione una tecla para continuar...', 13, 10, 0
ClockTitle db 'Modo Reloj  (A: alarma, C: cancelar, M: modo, ESC: salir)', 13, 10, 0
SwTitle    db 'Modo Cronometro (S: iniciar/pausar, R: reset, A: alarma, M: modo, ESC: salir)', 13, 10, 0
ExitMsg    db 13, 10, 'Programa finalizado.', 0

; --------------------------------------------------------------------
; Modules (see rubric "Makefiles y modularidad")
; --------------------------------------------------------------------
%include "video.asm"
%include "clock.asm"
%include "stopwatch.asm"
%include "alarm.asm"
%include "rtc_alarm.asm"
