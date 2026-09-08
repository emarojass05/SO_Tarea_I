; src/uefi/uefi_stopwatch.asm
; --------------------------------------------------------------------
; Modo Cronometro: contador de tiempo independiente, iniciado/pausado
; con S y reiniciado con R (ver KeyCheck en uefi_main.asm). En vez de
; contar ticks de 32 bits del BIOS (int 0x1A/AH=00h, como hace la
; version legacy), usa los segundos-del-dia derivados de EFI_TIME
; (Hour*3600+Min*60+Seg): GetTimeNow ya trae TimeBuf actualizado antes
; de llamar aqui, asi que no hace falta pedir la hora dos veces.
; --------------------------------------------------------------------

section .text

DrawStopwatch:
    call GetStopwatchElapsed    ; EAX = segundos transcurridos
    cmp  eax, [LastSwSecs]
    je   .skip
    mov  [LastSwSecs], eax

    xor  edx, edx
    mov  ecx, 60
    div  ecx                    ; EAX = minutos, EDX = segundos (0-59)
    push rdx
    mov  ecx, 100
    xor  edx, edx
    div  ecx                    ; EDX = minutos mod 100 (pantalla de 2 digitos)
    mov  eax, edx
    call SetCursorRow2
    call PrintDec2               ; minutos
    mov  ax, ':'
    call PrintChar
    pop  rax
    call PrintDec2               ; segundos
.skip:
    jmp KeyCheck

; Regresa en EAX el total de segundos transcurridos (corriendo o en pausa).
GetStopwatchElapsed:
    cmp  byte [SwRunning], 0
    je   .paused
    call SecsOfDay               ; EAX = segundos-del-dia actuales
    sub  eax, [SwBaseSecs]
    jns  .noWrap
    add  eax, 86400              ; cruzo medianoche mientras corria
.noWrap:
    add  eax, [SwElapsedSecs]
    ret
.paused:
    mov  eax, [SwElapsedSecs]
    ret

; Alterna entre corriendo/pausado, acumulando el tiempo transcurrido.
ToggleStopwatch:
    cmp  byte [SwRunning], 0
    je   .start
    call GetStopwatchElapsed
    mov  [SwElapsedSecs], eax
    mov  byte [SwRunning], 0
    ret
.start:
    call SecsOfDay
    mov  [SwBaseSecs], eax
    mov  byte [SwRunning], 1
    ret

; EAX = Hour*3600 + Minute*60 + Second, leidos de TimeBuf (uefi_time.asm)
SecsOfDay:
    push rcx
    movzx eax, byte [TimeBuf + TIME_Hour]
    imul eax, eax, 3600
    movzx ecx, byte [TimeBuf + TIME_Minute]
    imul ecx, ecx, 60
    add  eax, ecx
    movzx ecx, byte [TimeBuf + TIME_Second]
    add  eax, ecx
    pop  rcx
    ret

section .data
SwRunning     db 0        ; 0 = pausado, 1 = corriendo
SwBaseSecs    dd 0         ; segundos-del-dia cuando se (re)inicio
SwElapsedSecs dd 0         ; segundos acumulados mientras esta en pausa
LastSwSecs    dd -1
