# SO_Tarea_I
Para la implementaci´on de esta tarea ser´a necesario considerar que se implementar´a un programa (boot loader) realizado en ensamblador, el cual sea capaz de ejecutar una aplicaci´on llamada “Reloj/Cron´ometro con Alarma”.

## Dos bootloaders: Legacy BIOS y UEFI

El enunciado permite implementar el boot loader "utilizando Legacy Mode y UEFI", exigiendo que
al menos uno de los dos corra en hardware real (seccion 3.2). Este repositorio trae **ambos**:

- `src/boot/` + `src/app/` - bootloader Legacy BIOS/MBR (modo real de 16 bits), la version
  original. Usa las interrupciones de BIOS directamente: `int 0x13` (disco), `int 0x10`
  (pantalla), `int 0x16` (teclado) e `int 0x1A` (RTC), y programa el propio chip RTC para que
  dispare la alarma por una interrupcion de hardware real (IRQ8 / INT 70h) - ver
  `src/app/rtc_alarm.asm`.
- `src/uefi/` - aplicacion UEFI x64 (`BOOTX64.EFI`), agregada porque el equipo donde se prueba
  en hardware real no permite cambiar a modo de arranque Legacy. **100% ensamblador NASM, sin
  una sola linea de C** - ver "Por que UEFI no es un simple recompilado" abajo.

Las dos versiones son independientes (targets de Makefile separados); no comparten imagen de
disco. Si tu maquina si soporta Legacy, `make run` sigue sirviendo para probar esa version.

## Por que UEFI no es un simple recompilado

Un ejecutable UEFI x64 no puede usar interrupciones de BIOS (`int 0x10/0x13/0x16/0x1A`) en
absoluto - no hay modo real activo, asi que esas llamadas simplemente no existen en este
entorno. UEFI expone sus servicios como **protocolos**: tablas de punteros a funcion que se
invocan con la convencion de llamada x64 de Microsoft (RCX/RDX/R8/R9 + "shadow space" de 32
bytes + pila alineada a 16 bytes en cada `call`). Los offsets de esas tablas
(`EFI_SYSTEM_TABLE`, `EFI_SIMPLE_TEXT_OUTPUT/INPUT_PROTOCOL`, `EFI_RUNTIME_SERVICES`,
`EFI_BOOT_SERVICES`) estan fijados por la especificacion UEFI 2.x y se repiten identicos en
cualquier firmware x64 compatible, asi que `src/uefi/uefi_defs.inc` los declara a mano en vez
de depender de los headers en C de EDK2 - eso es lo que permite que todo el proyecto siga
siendo ensamblador puro (se compila con `nasm -f win64` y se enlaza con `lld-link`, sin ningun
compilador de C de por medio).

Mapeo de las llamadas usadas en la version BIOS a su equivalente UEFI:

| BIOS (legacy)                      | UEFI (`src/uefi/`)                                   |
|-------------------------------------|-------------------------------------------------------|
| `int 0x10` (pantalla)               | `ConOut->OutputString/ClearScreen/SetCursorPosition/SetAttribute/EnableCursor` |
| `int 0x16` (teclado)                | `ConIn->ReadKeyStroke` (+ `BootServices->WaitForEvent` para lectura bloqueante) |
| `int 0x1A` (hora del RTC via BIOS)  | `RuntimeServices->GetTime()` |
| Interrupcion real IRQ8/INT 70h del RTC (alarma) | Comparacion de `GetTime()` contra la alarma en cada vuelta del loop principal (`CheckAlarmMatch`, `src/uefi/uefi_alarm.asm`) |
| Puertos 0x40-0x43/0x61 (beep)       | Los mismos puertos, con `in`/`out` (best-effort: UEFI no tiene un protocolo estandar para el parlante) |

El punto que vale la pena discutir con el profesor (la tarea invita a esto en la seccion 7 ante
cualquier ambiguedad): el enunciado pide "la interrupcion de RTC provista por el BIOS" para
comparar la hora (20% de la nota incluye "uso de interrupciones... incluyendo RTC"). Bajo UEFI
de 64 bits esa interrupcion de BIOS no existe fisicamente; `GetTime()` es la via nativa de UEFI
para leer el mismo chip RTC, pero es una llamada a funcion, no una interrupcion de software
literal. Se opto por este camino (en vez de instalar un manejador de interrupcion propio sobre
el IDT del firmware) porque es el que de verdad funciona de forma confiable en hardware real
variado - manipular el IDT/PIC bajo UEFI es fragil y, en un equipo "legacy-free" moderno, puede
no tener ni el PIC 8259 mapeado como se espera.

## Compilar y probar

```sh
# Legacy BIOS (como antes)
make run                 # o `make` + qemu-system-x86_64 -fda build/disk.img

# UEFI
make uefi                # genera build/BOOTX64.EFI y build/disk_uefi.img
make run-uefi             # QEMU + OVMF, con ventana grafica
make run-uefi-headless    # QEMU + OVMF, sin pantalla (OVMF espeja la consola por serial)
```

Requisitos adicionales para el target UEFI (ademas de `nasm`, que ya hacia falta):
`lld` (da el comando `lld-link`), `mtools` (`mformat`/`mmd`/`mcopy`) para armar la imagen FAT, y
`ovmf` solo si vas a probar en QEMU (no hace falta para arrancar en hardware real). En
Debian/Ubuntu: `sudo apt install lld mtools ovmf`.

## Probar en hardware real (USB)

`build/disk_uefi.img` es una imagen FAT "superfloppy" (sin tabla de particiones) con
`/EFI/BOOT/BOOTX64.EFI` - la ruta que cualquier firmware UEFI x64 busca por defecto en un medio
removible sin entrada de arranque registrada. Para escribirla a un USB (**revisa dos veces
`/dev/sdX`, esto borra el dispositivo por completo**):

```sh
sudo dd if=build/disk_uefi.img of=/dev/sdX bs=4M status=progress && sync
```

Despues arranca la laptop desde ese USB (menu de arranque / boot order en el firmware). Si tu
firmware especifico no reconoce una imagen sin tabla de particiones, la alternativa es
construir una con GPT y una particion ESP (FAT32) real usando `parted`/`sgdisk` en vez del
`dd` + `mformat` directo que usa el Makefile - avisame si llegas a necesitarlo y lo agregamos.
