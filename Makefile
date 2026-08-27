ASM      := nasm
QEMU     := qemu-system-x86_64

BUILD     := build
BOOT_SRC  := src/boot/boot.asm
APP_SRC   := src/app/app.asm
BOOT_BIN  := $(BUILD)/boot.bin
APP_BIN   := $(BUILD)/app.bin
IMAGE     := $(BUILD)/disk.img

.PHONY: all run clean

all: $(IMAGE)

$(BUILD):
	mkdir -p $(BUILD)

$(BOOT_BIN): $(BOOT_SRC) | $(BUILD)
	$(ASM) -f bin $(BOOT_SRC) -o $(BOOT_BIN)

$(APP_BIN): $(APP_SRC) | $(BUILD)
	$(ASM) -f bin $(APP_SRC) -o $(APP_BIN)

$(IMAGE): $(BOOT_BIN) $(APP_BIN)
	dd if=/dev/zero of=$(IMAGE) bs=512 count=2880 status=none
	dd if=$(BOOT_BIN) of=$(IMAGE) conv=notrunc status=none
	dd if=$(APP_BIN) of=$(IMAGE) seek=1 conv=notrunc status=none

run: $(IMAGE)
	$(QEMU) -fda $(IMAGE) -display curses

clean:
	rm -rf $(BUILD)