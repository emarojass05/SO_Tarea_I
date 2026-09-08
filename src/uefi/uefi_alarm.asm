; src/uefi/uefi_alarm.asm
; --------------------------------------------------------------------
; UI de la alarma: configurar HH:MM (SetAlarmPrompt) y la pantalla de
; repique (AlarmRing) - mismo diseno que alarm.asm en la version BIOS.
;
; Diferencia de fondo con la version BIOS/legacy: alla la coincidencia
; HH:MM la detecta el propio chip RTC por hardware, disparando IRQ8 de
; verdad (rtc_alarm.asm instala un manejador en INT 70h). Bajo UEFI de
; 64 bits eso no es viable de forma portable: el IDT lo controla el
; firmware, no hay PIC clasico garantizado en hardware "legacy-free", y
; instalar un manejador propio ahi es fragil y dificil de depurar en
; una maquina especifica. En su lugar, CheckAlarmMatch compara la hora
; ya leida por GetTimeNow (EFI_RUNTIME_SERVICES->GetTime, que sigue
; siendo la misma fuente de tiempo real de hardware) contra la alarma
; en cada vuelta del loop principal. Sigue siendo "tiempo real provisto
; por hardware" - el RTC sigue siendo quien manda - solo que el chequeo
; de coincidencia ahora es software en vez de una interrupcion.
; --------------------------------------------------------------------

section .text

; Se llama una vez por vuelta del loop, justo despues de GetTimeNow.
; Deja AlarmTriggered en 1 en el instante en que coincide HH:MM
; (con enclavamiento: no se vuelve a activar cada segundo dentro del
; mismo minuto ya disparado).
CheckAlarmMatch:
    cmp  byte [AlarmSet], 0
    je   .no
    cmp  byte [AlarmTriggered], 0
    jne  .no
    movzx eax, byte [TimeBuf + TIME_Hour]
    cmp  al, [AlarmHour]
    jne  .no
    movzx eax, byte [TimeBuf + TIME_Minute]
    cmp  al, [AlarmMin]
    jne  .no
    mov  byte [AlarmTriggered], 1
.no:
    ret

; Parpadeo a pantalla completa + beep del parlante (best-effort), en
; loop hasta que 'C' cancela.
AlarmRing:
    call ClearScreen
.ringLoop:
    xor  byte [FlashState], 1
    cmp  byte [FlashState], 0
    je   .colorA
    mov  byte [FlashAttr], EFI_WHITE_ON_RED
    jmp  .doFlash
.colorA:
    mov  byte [FlashAttr], EFI_WHITE_ON_BLUE
.doFlash:
    call FillScreenAttr
    lea  rsi, [rel AlarmMsg]
    call PrintString
    call Beep

    call ReadKeyPoll
    jnc  .noKeyRing
    movzx eax, word [EfiKeyBuf + KEY_UnicodeChar]
    cmp  al, 'c'
    je   .cancelAlarm
    cmp  al, 'C'
    je   .cancelAlarm
.noKeyRing:
    mov  ecx, 300000        ; ~300ms entre parpadeos
    call StallUs
    jmp  .ringLoop
.cancelAlarm:
    mov  byte [AlarmSet], 0
    mov  byte [AlarmTriggered], 0
    call ShowTitle
    jmp  MainLoop

; Prompt interactivo de HH:MM (4 teclas digito, ecoadas). Se guardan
; como binario simple (0-23 / 0-59): EFI_TIME tambien es binario, asi
; que -a diferencia de la version BIOS- no hace falta empaquetar BCD.
; Una hora fuera de rango se rechaza y el prompt reinicia.
SetAlarmPrompt:
    call ClearScreen
.retry:
    lea  rsi, [rel SetAlarmMsg]
    call PrintString

    call ReadDigit
    mov  [InHH], al
    call ReadDigit
    mov  bl, al
    movzx eax, byte [InHH]
    imul eax, eax, 10
    add  al, bl
    cmp  al, 23
    ja   .badInput
    mov  [AlarmHour], al

    mov  ax, ':'
    call PrintChar

    call ReadDigit
    mov  [InMM], al
    call ReadDigit
    mov  bl, al
    movzx eax, byte [InMM]
    imul eax, eax, 10
    add  al, bl
    cmp  al, 59
    ja   .badInput
    mov  [AlarmMin], al

    mov  byte [AlarmSet], 1
    mov  byte [AlarmTriggered], 0

    lea  rsi, [rel AlarmSetOkMsg]
    call PrintString
    call ReadKeyBlocking
    call ShowTitle
    ret

.badInput:
    call ClearScreen
    lea  rsi, [rel AlarmBadMsg]
    call PrintString
    jmp  .retry

; Imprime "Alarma: HH:MM" o "Alarma: --:--" + CRLF (usado por ShowTitle).
PrintAlarmStatus:
    lea  rsi, [rel AlarmLabel]
    call PrintString
    cmp  byte [AlarmSet], 0
    je   .none
    movzx eax, byte [AlarmHour]
    call PrintDec2
    mov  ax, ':'
    call PrintChar
    movzx eax, byte [AlarmMin]
    call PrintDec2
    jmp  .done
.none:
    lea  rsi, [rel NoAlarmMsg]
    call PrintString
.done:
    lea  rsi, [rel CrLf]
    call PrintString
    ret

section .data
AlarmSet       db 0          ; 0 = sin alarma configurada, 1 = configurada
AlarmTriggered db 0          ; 0 = no repica, 1 = repicando
AlarmHour      db 0          ; binario, 0-23
AlarmMin       db 0          ; binario, 0-59
FlashAttr      db 0
FlashState     db 0
InHH           db 0
InMM           db 0

AlarmLabel    dw __utf16__(`Alarma: `), 0
NoAlarmMsg    dw __utf16__(`--:--`), 0
CrLf          dw __utf16__(`\r\n`), 0
SetAlarmMsg   dw __utf16__(`Configurar alarma. Ingrese hora HH: `), 0
AlarmBadMsg   dw __utf16__(`Hora invalida (HH 00-23, MM 00-59). Intente de nuevo.\r\n`), 0
AlarmSetOkMsg dw __utf16__(`\r\nAlarma configurada. Presione una tecla...\r\n`), 0
AlarmMsg      dw __utf16__(`*** ALARMA *** Presione C para cancelar\r\n`), 0
