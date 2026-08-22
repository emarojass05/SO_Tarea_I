; src/boot/boot.asm
; Da la bienvenida y detiene la ejecucion mientras se desarrolla la aplicacion
; (Reloj/Cronometro con Alarma). El BIOS lo carga en la direccion 0x7C00.

bits 16
org 0x7C00

start:
    cli                 ; deshabilita interrupciones mientras configuramos segmentos
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti                 ; reactiva interrupciones

    mov si, msg_bienvenida
    call print_string

    ; TODO: aqui se debe cargar/saltar a la aplicacion Reloj/Cronometro
    ; (leer sectores adicionales del disco con INT 13h y hacer jmp)

.hang:
    hlt
    jmp .hang

; --------------------------------------------------
; print_string: imprime en pantalla usando teletype BIOS (INT 10h/AH=0x0E)
; Entrada: SI -> puntero a string terminada en 0
; --------------------------------------------------
print_string:
    pusha
    mov ah, 0x0E
.loop:
    lodsb
    cmp al, 0
    je .done
    int 0x10
    jmp .loop
.done:
    popa
    ret

msg_bienvenida db 'Bienvenido - Reloj/Cronometro con Alarma', 13, 10, 0

; Relleno hasta 510 bytes + firma de arranque obligatoria
times 510-($-$$) db 0
dw 0xAA55