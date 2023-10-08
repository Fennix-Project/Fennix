
include Makefile.conf

.PHONY: default tools clean

# First rule
default:
	$(error Please specify a target)

# For tap0
# -netdev tap,id=usernet0,ifname=tap0,script=no,downscript=no
QEMU = ./$(QEMU_PATH)$(QEMU_ARCH)
QEMUFLAGS := -display gtk

ifeq ($(OSARCH), amd64)
QEMUFLAGS += -device vmware-svga -M q35 \
			 -usb \
			 -usbdevice mouse \
			 -net user \
			 -netdev user,id=usernet0 \
			 -device e1000,netdev=usernet0,mac=00:69:96:00:42:00 \
			 -object filter-dump,id=usernet0,netdev=usernet0,file=network.dmp,maxlen=1024 \
			 -serial file:serial.log \
			 -serial file:profiler.log \
			 -serial file:serial3.dmp \
			 -serial file:serial4.dmp \
			 -parallel file:parallel.log \
			 -device ahci,id=ahci \
			 -drive id=bootdsk,file=$(OSNAME).iso,format=raw,if=none \
			 -device ide-hd,drive=bootdsk,bus=ahci.0 \
			 -drive id=disk,file=qemu-disk.img,format=raw,if=none \
			 -device ide-hd,drive=disk,bus=ahci.1 \
			 -audiodev pa,id=pa1,server=/run/user/1000/pulse/native \
			 -machine pcspk-audiodev=pa1 \
			 -device AC97,audiodev=pa1
else ifeq ($(OSARCH), i386)
QEMUFLAGS += -M q35 \
			 -usb \
			 -usbdevice mouse \
			 -net user \
			 -netdev user,id=usernet0 \
			 -device e1000,netdev=usernet0,mac=00:69:96:00:42:00 \
			 -object filter-dump,id=usernet0,netdev=usernet0,file=network.dmp,maxlen=1024 \
			 -serial file:serial.log \
			 -serial file:profiler.log \
			 -serial file:serial3.dmp \
			 -serial file:serial4.dmp \
			 -parallel file:parallel.log \
			 -hda $(OSNAME).iso \
			 -audiodev pa,id=pa1,server=/run/user/1000/pulse/native \
			 -machine pcspk-audiodev=pa1 \
			 -device AC97,audiodev=pa1
else ifeq ($(OSARCH), aarch64)
QEMUFLAGS += -M raspi3b \
			 -cpu cortex-a57 \
			 -serial file:serial.log \
			 -serial file:profiler.log \
			 -serial file:serial3.dmp \
			 -serial file:serial4.dmp \
			 -kernel $(OSNAME).img
endif

doxygen:
	mkdir -p doxygen-doc
	doxygen Doxyfile
	doxygen Kernel/Doxyfile
	doxygen Lynx/Doxyfile
	doxygen Userspace/Doxyfile
	doxygen Modules/Doxyfile

qemu_vdisk:
ifneq (,$(wildcard ./qemu-disk.img))
	$(info qemu-disk.img Already exists)
else
	dd if=/dev/zero of=qemu-disk.img bs=1024K count=4000
endif

# Install necessary packages, build cross-compiler etc...
tools:
	make --quiet -C tools all
	make --quiet -C Kernel prepare
	make --quiet -C Lynx prepare
	make --quiet -C Userspace prepare
	make --quiet -C Modules prepare

build: build_lynx build_kernel build_userspace build_modules build_image

dump:
	make --quiet -C Kernel dump

rebuild: clean build

ifeq ($(QUIET_BUILD), 1)
MAKE_QUIET_FLAG = --quiet
endif

build_lynx:
ifeq ($(BOOTLOADER), lynx)
	make $(MAKE_QUIET_FLAG) -C Lynx build
endif

build_kernel:
ifeq ($(BUILD_KERNEL), 1)
	make -j$(shell nproc) $(MAKE_QUIET_FLAG) -C Kernel build
endif

build_userspace:
ifeq ($(BUILD_USERSPACE), 1)
	make $(MAKE_QUIET_FLAG) -C Userspace build
endif

build_modules:
ifeq ($(BUILD_MODULES), 1)
	make $(MAKE_QUIET_FLAG) -C Modules build
endif

build_image:
	mkdir -p iso_tmp_data
	mkdir -p initrd_tmp_data
	cp -r initrd/* initrd_tmp_data/
ifeq ($(BUILD_MODULES), 1)
	cp -r Modules/out/* initrd_tmp_data/modules/
endif
ifeq ($(BUILD_USERSPACE), 1)
	cp -r Userspace/out/* initrd_tmp_data/
endif
#	tar czf initrd.tar.gz -C initrd_tmp_data/ ./ --format=ustar
	tar cf initrd.tar.gz -C initrd_tmp_data/ ./ --format=ustar
	cp Kernel/kernel.fsys initrd.tar.gz \
		iso_tmp_data/
ifeq ($(BOOTLOADER), lynx)
	cp tools/lynx.cfg Lynx/loader.bin Lynx/efi-loader.bin iso_tmp_data/
	xorriso -as mkisofs -b loader.bin \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		--efi-boot efi-loader.bin -V FENNIX \
		-efi-boot-part --efi-boot-image --protective-msdos-label \
		iso_tmp_data -o $(OSNAME).iso
endif
ifeq ($(BOOTLOADER), limine)
	cp tools/limine.cfg $(LIMINE_FOLDER)/limine.sys $(LIMINE_FOLDER)/limine-cd.bin $(LIMINE_FOLDER)/limine-cd-efi.bin iso_tmp_data/
	xorriso -as mkisofs -quiet -b limine-cd.bin \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		--efi-boot limine-cd-efi.bin -V FENNIX \
		-efi-boot-part --efi-boot-image --protective-msdos-label \
		iso_tmp_data -o $(OSNAME).iso
endif
ifeq ($(BOOTLOADER), grub)
# TODO: Add custom language support for GRUB or detect the system language using "echo $LANG | cut -d . -f 1" and set "lang" variable inside grub.cfg
	mkdir -p iso_tmp_data/boot
	mkdir -p iso_tmp_data/boot/grub
	cp tools/grub.cfg iso_tmp_data/boot/grub/
	grub-mkrescue -o $(OSNAME).iso iso_tmp_data
endif
ifeq ($(OSARCH), aarch64)
	$(COMPILER_PATH)/$(COMPILER_ARCH)objcopy Kernel/kernel.fsys -O binary $(OSNAME).img
endif

ifeq ($(OSARCH), amd64)
QEMU_UEFI_BIOS = -bios /usr/share/qemu/OVMF.fd
endif
# ifeq ($(OSARCH), aarch64)
# QEMU_UEFI_BIOS = -bios -bios /usr/share/AAVMF/AAVMF_CODE.fd
# endif

ifeq ($(OSARCH), amd64)
QEMU_SMP_DBG = -smp $(shell echo $(shell nproc)/4 | bc)
QEMU_SMP = -smp $(shell nproc)
endif

ifeq ($(OSARCH), i386)
QEMU_SMP_DBG = -smp $(shell echo $(shell nproc)/4 | bc)
QEMU_SMP = -smp $(shell nproc)
endif

ifeq ($(OSARCH), aarch64)
QEMU_SMP_DBG = -smp 4
QEMU_SMP = -smp 4
endif

ifeq ($(OSARCH), amd64)
QEMUHWACCELERATION = -machine q35 -enable-kvm
QEMUMEMORY = -m 4G
else ifeq ($(OSARCH), i386)
QEMUHWACCELERATION = -machine q35 -enable-kvm
QEMUMEMORY = -m 4G
else ifeq ($(OSARCH), aarch64)
QEMUHWACCELERATION =
QEMUMEMORY = -m 1G
endif

vscode_debug_only:
	rm -f serial.log profiler.log serial3.dmp serial4.dmp network.dmp parallel.log
	$(QEMU) -S -gdb tcp::1234 -d int -no-reboot -no-shutdown $(QEMU_UEFI_BIOS) -m 512M $(QEMUFLAGS) $(QEMU_SMP_DBG)

vscode_debug: build_lynx build_kernel build_userspace build_modules build_image vscode_debug_only

qemu: qemu_vdisk
	rm -f serial.log profiler.log serial3.dmp serial4.dmp network.dmp parallel.log
#	touch serial.log parallel.log
#	x-terminal-emulator -e tail -f serial.log &
#	x-terminal-emulator -e tail -f parallel.log &
	$(QEMU) $(QEMU_UEFI_BIOS) -cpu host $(QEMUFLAGS) $(QEMUHWACCELERATION) $(QEMUMEMORY) $(QEMU_SMP)

qemubios: qemu_vdisk
	rm -f serial.log profiler.log serial3.dmp serial4.dmp network.dmp parallel.log
	$(QEMU) -cpu host $(QEMUFLAGS) $(QEMUHWACCELERATION) $(QEMUMEMORY) $(QEMU_SMP)

run: build qemu

clean:
	rm -rf doxygen-doc iso_tmp_data initrd_tmp_data
	rm -f initrd.tar.gz $(OSNAME).iso $(OSNAME).img
	make -C Kernel clean
	make -C Lynx clean
	make -C Userspace clean
	make -C Modules clean
