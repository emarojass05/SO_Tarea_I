; src/uefi/uefi_video.asm
; --------------------------------------------------------------------
; Low-level screen/keyboard helpers shared by every mode, hablando con
; los protocolos UEFI (EFI_SIMPLE_TEXT_OUTPUT/INPUT_PROTOCOL) en vez de
; las interrupciones de BIOS que usa la version legacy (int 0x10/0x16):
; un ejecutable UEFI x64 no puede invocar esas interrupciones de modo
; real en absoluto, asi que este es el reemplazo obligado, no una
; eleccion de estilo.
;
; Convencion interna: nuestras propias rutinas (no las de firmware) se
; pasan la cadena/valor en RSI/AX, igual que el original usaba SI/AL -
; RSI, RBX y demas registros "non-volatile" del ABI de Windows x64 los
; preserva cualquier funcion de UEFI que llamemos, asi que podemos
; seguir usandolos igual que el codigo original usaba SI a traves de
; las llamadas a INT 10h/16h.
; --------------------------------------------------------------------

section .text

; RSI -> cadena CHAR16 terminada en NUL
PrintString:
    EFI_PROLOGUE
    mov  rax, [gConOut]
    mov  rcx, rax
    mov  rdx, rsi
    call qword [rax + TXTOUT_OutputString]
    EFI_EPILOGUE
    ret

; AX = caracter CHAR16 a imprimir
PrintChar:
    EFI_PROLOGUE
    mov  [CharBuf], ax
    mov  word [CharBuf + 2], 0
    mov  rax, [gConOut]
    mov  rcx, rax
    lea  rdx, [rel CharBuf]
    call qword [rax + TXTOUT_OutputString]
    EFI_EPILOGUE
    ret

; AL = valor binario 0-99 -> dos digitos CHAR16 (con cero a la izquierda)
PrintDec2:
    push rbx
    xor  ah, ah
    mov  bl, 10
    div  bl                ; AL = decenas, AH = unidades
    mov  bh, ah
    add  al, '0'
    xor  ah, ah
    call PrintChar
    mov  al, bh
    add  al, '0'
    xor  ah, ah
    call PrintChar
    pop  rbx
    ret

; Antes de limpiar, siempre repone el color por defecto: FillScreenAttr
; (usada por AlarmRing para el parpadeo rojo/azul) deja el atributo de
; ConOut puesto ahi hasta que algo lo cambie explicitamente -a diferencia
; de la version BIOS, UEFI no lo resetea solo- asi que sin esto la
; pantalla se quedaba pintada de rojo/azul despues de cancelar la alarma.
ClearScreen:
    EFI_PROLOGUE
    mov  rax, [gConOut]
    mov  rcx, rax
    mov  rdx, EFI_LIGHTGRAY
    call qword [rax + TXTOUT_SetAttribute]
    mov  rax, [gConOut]
    mov  rcx, rax
    call qword [rax + TXTOUT_ClearScreen]
    EFI_EPILOGUE
    ret

HideCursor:
    EFI_PROLOGUE
    mov  rax, [gConOut]
    mov  rcx, rax
    xor  rdx, rdx
    call qword [rax + TXTOUT_EnableCursor]
    EFI_EPILOGUE
    ret

; Restaura el cursor visible, deshaciendo HideCursor. Se llama al salir
; para no dejar la terminal con el cursor invisible tras finalizar.
ShowCursor:
    EFI_PROLOGUE
    mov  rax, [gConOut]
    mov  rcx, rax
    mov  rdx, 1
    call qword [rax + TXTOUT_EnableCursor]
    EFI_EPILOGUE
    ret

SetCursorRow2:
    EFI_PROLOGUE
    mov  rax, [gConOut]
    mov  rcx, rax
    xor  rdx, rdx          ; Column = 0
    mov  r8, 2              ; Row = 2
    call qword [rax + TXTOUT_SetCursorPosition]
    EFI_EPILOGUE
    ret

; Pinta toda la pantalla con el atributo en [FlashAttr] (alarm.asm) y
; deja el cursor en el origen. SetAttribute solo fija el color para lo
; que se imprima despues; es ClearScreen quien realmente repinta todas
; las celdas usando ese color de fondo, por eso van juntos.
FillScreenAttr:
    EFI_PROLOGUE
    mov  rax, [gConOut]
    mov  rcx, rax
    movzx rdx, byte [FlashAttr]
    call qword [rax + TXTOUT_SetAttribute]
    mov  rax, [gConOut]
    mov  rcx, rax
    call qword [rax + TXTOUT_ClearScreen]
    EFI_EPILOGUE
    ret

; Bloqueante: espera a que haya una tecla disponible (BootServices->
; WaitForEvent sobre ConIn->WaitForKey) y la consume en EfiKeyBuf.
; Equivalente UEFI de "int 0x16, AH=0" (lectura bloqueante).
ReadKeyBlocking:
    EFI_PROLOGUE
    mov  rax, [gConIn]
    mov  rax, [rax + TXTIN_WaitForKey]
    mov  [gWaitEvt], rax
    mov  rcx, 1
    lea  rdx, [rel gWaitEvt]
    lea  r8, [rel gWaitIdx]
    mov  rax, [gBS]
    call qword [rax + BS_WaitForEvent]

    mov  rax, [gConIn]
    mov  rcx, rax
    lea  rdx, [rel EfiKeyBuf]
    call qword [rax + TXTIN_ReadKeyStroke]
    EFI_EPILOGUE
    ret

; No bloqueante: CF=1 si se leyo una tecla (queda en EfiKeyBuf), CF=0 si
; no habia ninguna disponible. Equivalente UEFI de sondear con
; "int 0x16, AH=1" seguido de "AH=0" - aqui ReadKeyStroke hace ambas
; cosas en una sola llamada (si no hay tecla, regresa EFI_NOT_READY).
ReadKeyPoll:
    EFI_PROLOGUE
    mov  rax, [gConIn]
    mov  rcx, rax
    lea  rdx, [rel EfiKeyBuf]
    call qword [rax + TXTIN_ReadKeyStroke]
    EFI_EPILOGUE
    test rax, rax
    jnz  .none
    stc
    ret
.none:
    clc
    ret

; Lectura bloqueante de una tecla '0'-'9'; la ecoa y regresa 0-9 en AL.
ReadDigit:
.wait:
    call ReadKeyBlocking
    mov  ax, word [EfiKeyBuf + KEY_UnicodeChar]
    cmp  al, '0'
    jb   .wait
    cmp  al, '9'
    ja   .wait
    mov  bl, al             ; BL sobrevive la llamada (non-volatile)
    call PrintChar          ; ecoa el digito (AX sigue con el caracter)
    mov  al, bl
    sub  al, '0'
    ret

; RCX = microsegundos a esperar (BootServices->Stall). Reemplaza el
; busy-wait de Delay en la version BIOS.
StallUs:
    EFI_PROLOGUE
    mov  rax, [gBS]
    call qword [rax + BS_Stall]
    EFI_EPILOGUE
    ret

; Beep corto por el parlante del PC (best-effort). Sigue exactamente el
; mismo truco de puertos que la version BIOS (canal 2 del PIT + puerto
; 0x61): las instrucciones IN/OUT funcionan igual bajo UEFI porque la
; app corre en anillo 0, pero no hay una forma "oficial" de UEFI de
; pedirle sonido al parlante, asi que esto es best-effort - si el
; firmware no expone el PIT clasico de la forma esperada, simplemente
; no suena, sin romper nada. El requisito de la tarea permite efecto
; visual y/o sonido, y el parpadeo de AlarmRing ya cumple por si solo.
Beep:
    push rax
    mov  al, 0xB6
    out  0x43, al
    mov  ax, 1193
    out  0x42, al
    mov  al, ah
    out  0x42, al
    in   al, 0x61
    or   al, 0x03
    out  0x61, al
    mov  ecx, 60000
    call StallUs
    in   al, 0x61
    and  al, 0xFC
    out  0x61, al
    pop  rax
    ret

section .data
CharBuf: dw 0, 0
