ASM      := nasm
QEMU     := qemu-system-x86_64
LLD_LINK := lld-link

BUILD     := build

# ---------------------------------------------------------------------
# Legacy BIOS (MBR, modo real 16 bits) - stage1 boot.asm + app.asm
# ---------------------------------------------------------------------
BOOT_SRC  := src/boot/boot.asm
APP_SRC   := src/app/app.asm
APP_MODS  := src/app/rtc_alarm.asm src/app/video.asm src/app/clock.asm src/app/stopwatch.asm src/app/alarm.asm
BOOT_BIN  := $(BUILD)/boot.bin
APP_BIN   := $(BUILD)/app.bin
IMAGE     := $(BUILD)/disk.img

# ---------------------------------------------------------------------
# UEFI (x64, aplicacion PE32+ en NASM puro - ver README para el porque)
# ---------------------------------------------------------------------
UEFI_SRC   := src/uefi/uefi_main.asm
UEFI_MODS  := src/uefi/uefi_defs.inc src/uefi/uefi_video.asm src/uefi/uefi_time.asm \
              src/uefi/uefi_clock.asm src/uefi/uefi_stopwatch.asm src/uefi/uefi_alarm.asm
UEFI_OBJ   := $(BUILD)/uefi_main.obj
UEFI_EFI   := $(BUILD)/BOOTX64.EFI
UEFI_IMAGE := $(BUILD)/disk_uefi.img
# Firmware OVMF para probar en QEMU (solo hace falta para `run-uefi*`,
# NO para arrancar en hardware real). Ruta tipica en Debian/Ubuntu tras
# `sudo apt install ovmf`; ajustar si el paquete de tu distro la deja
# en otro lugar (p. ej. /usr/share/edk2-ovmf/x64/OVMF.fd en Arch).
OVMF_FD    := /usr/share/ovmf/OVMF.fd

.PHONY: all run clean uefi run-uefi run-uefi-headless

all: $(IMAGE)

$(BUILD):
	mkdir -p $(BUILD)

$(BOOT_BIN): $(BOOT_SRC) | $(BUILD)
	$(ASM) -f bin $(BOOT_SRC) -o $(BOOT_BIN)

$(APP_BIN): $(APP_SRC) $(APP_MODS) | $(BUILD)
	$(ASM) -f bin -I $(dir $(APP_SRC)) $(APP_SRC) -o $(APP_BIN)

$(IMAGE): $(BOOT_BIN) $(APP_BIN)
	dd if=/dev/zero of=$(IMAGE) bs=512 count=2880 status=none
	dd if=$(BOOT_BIN) of=$(IMAGE) conv=notrunc status=none
	dd if=$(APP_BIN) of=$(IMAGE) seek=1 conv=notrunc status=none

run: $(IMAGE)
	$(QEMU) -fda $(IMAGE) -display curses

# --- UEFI --------------------------------------------------------------
uefi: $(UEFI_IMAGE)

$(UEFI_OBJ): $(UEFI_SRC) $(UEFI_MODS) | $(BUILD)
	$(ASM) -f win64 -I $(dir $(UEFI_SRC)) $(UEFI_SRC) -o $(UEFI_OBJ)

$(UEFI_EFI): $(UEFI_OBJ)
	$(LLD_LINK) /subsystem:efi_application /entry:efi_main /machine:x64 /nodefaultlib /out:$(UEFI_EFI) $(UEFI_OBJ)

# Imagen FAT "superfloppy" (sin tabla de particiones) con
# /EFI/BOOT/BOOTX64.EFI: el nombre y la ruta por defecto que cualquier
# firmware UEFI x64 busca al arrancar de un medio removible (USB) que
# no tiene una entrada de arranque registrada. Ver README para como
# escribirla a un USB y para la alternativa GPT+ESP si tu firmware
# especifico no la reconoce asi.
$(UEFI_IMAGE): $(UEFI_EFI)
	dd if=/dev/zero of=$(UEFI_IMAGE) bs=1M count=64 status=none
	mformat -i $(UEFI_IMAGE) -F ::
	mmd -i $(UEFI_IMAGE) ::/EFI
	mmd -i $(UEFI_IMAGE) ::/EFI/BOOT
	mcopy -i $(UEFI_IMAGE) $(UEFI_EFI) ::/EFI/BOOT/BOOTX64.EFI

# Prueba grafica en QEMU (requiere entorno con pantalla / X11).
run-uefi: $(UEFI_IMAGE)
	$(QEMU) -machine q35 -m 256 -bios $(OVMF_FD) -drive format=raw,file=$(UEFI_IMAGE)

# Prueba sin pantalla: OVMF espeja ConOut tambien al puerto serie, asi
# que esto sirve para probar por SSH / sin entorno grafico.
run-uefi-headless: $(UEFI_IMAGE)
	$(QEMU) -machine q35 -m 256 -bios $(OVMF_FD) -drive format=raw,file=$(UEFI_IMAGE) -display none -serial mon:stdio

clean:
	rm -rf $(BUILD)