#
# Makefile - build a kernel+filesystem image for stand-alone Linux booting
#
# Copyright (C) 2012 ARM Limited. All rights reserved.
#
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE.txt file.

# VE
PHYS_OFFSET	:= 0x80000000
UART_BASE	:= 0x1c090000
SYSREGS_BASE	:= 0x1c010000
GIC_DIST_BASE	:= 0x2c001000
GIC_CPU_BASE	:= 0x2c002000
CNTFRQ		:= 0x01800000	# 24Mhz

#INITRD_FLAGS	:= -DUSE_INITRD
ACPI_FLAGS      := -DUSE_ACPI
CPPFLAGS        += $(INITRD_FLAGS) $(ACPI_FLAGS)

BOOTLOADER	:= boot.S
MBOX_OFFSET	:= 0xfff8
XEN             := Xen
XEN_OFFSET      := 0xA00000
KERNEL		:= Image
KERNEL_OFFSET	:= 0x80000
LD_SCRIPT	:= model.lds.S
IMAGE		:= linux-system.axf
XIMAGE		:= xen-system.axf
BUILD_DTB	:= y

FILESYSTEM	:= filesystem.cpio.gz
FS_OFFSET	:= 0x10000000
FILESYSTEM_START:= $(shell echo $$(($(PHYS_OFFSET) + $(FS_OFFSET))))
FILESYSTEM_SIZE	:= $(shell stat -Lc %s $(FILESYSTEM) 2>/dev/null || echo 0)
FILESYSTEM_END	:= $(shell echo $$(($(FILESYSTEM_START) + $(FILESYSTEM_SIZE))))

ACPI           := tables.acpi
ACPI_OFFSET    := 0x08100000
ACPI_START     := $(shell echo $$(($(PHYS_OFFSET) + $(ACPI_OFFSET))))
ACPI_SIZE      := $(shell stat -Lc %s $(ACPI) 2>/dev/null || echo 0)
ACPI_END       := $(shell echo $$(($(ACPI_START) + $(ACPI_SIZE))))

ifeq ($(BUILD_DTB),y)
FDT_SRC		:= rtsm_ve-aemv8a.dts
FDT_INCL_REGEX	:= \(/include/[[:space:]]*"\)\([^"]\+\)\(".*\)
FDT_DEPS	:= $(FDT_SRC) $(addprefix $(dir $(FDT_SRC)), $(shell sed -ne 'sq$(strip $(FDT_INCL_REGEX)q\2q p' < $(FDT_SRC))))
endif
FDT_OFFSET	:= 0x08000000

BOOTARGS_COMMON	:= "console=ttyAMA0 earlyprintk=pl011,0x1c090000 $(BOOTARGS_EXTRA)"

CHOSEN_NODE	:= chosen {
ifneq (,$(findstring USE_INITRD,$(CPPFLAGS)))
BOOTARGS	:= "$(BOOTARGS_COMMON)"
CHOSEN_NODE	+=	bootargs = \"$(BOOTARGS)\";			\
			linux,initrd-start = <$(FILESYSTEM_START)>;	\
			linux,initrd-end = <$(FILESYSTEM_END)>;

ifneq (,$(findstring USE_ACPI,$(CPPFLAGS)))
CHOSEN_NODE    +=	linux,acpi-start = <$(ACPI_START)>;	\
			linux,acpi-len  = <$(ACPI_SIZE)>;
endif

else
BOOTARGS	:= "root=/dev/nfs nfsroot=\<serverip\>:\<rootfs\>,tcp rw ip=dhcp $(BOOTARGS_COMMON)"
CHOSEN_NODE	:= chosen {						\
			bootargs = \"$(BOOTARGS)\";

ifneq (,$(findstring USE_ACPI,$(CPPFLAGS)))
CHOSEN_NODE     +=      linux,acpi-start = <$(ACPI_START)>;             \
			linux,acpi-len  = <$(ACPI_SIZE)>;
endif

endif
CHOSEN_NODE     += };

CROSS_COMPILE	?= aarch64-none-linux-gnu-
CC		:= $(CROSS_COMPILE)gcc
LD		:= $(CROSS_COMPILE)ld
DTC		:= $(if $(wildcard ./dtc), ./dtc, $(shell which dtc))

all: $(IMAGE) $(XIMAGE)

clean:
	rm -f $(IMAGE) boot.o model.lds
ifeq ($(BUILD_DTB),y)
	rm -f fdt.dtb
endif
	rm -f $(XIMAGE) boot.xen.o model.xen.lds

$(IMAGE): boot.o model.lds fdt.dtb $(KERNEL) $(FILESYSTEM)
	$(LD) -o $@ --script=model.lds

$(XIMAGE): boot.xen.o model.xen.lds fdt.dtb $(XEN) $(KERNEL) $(FILESYSTEM)
	$(LD) -o $@ --script=model.xen.lds

boot.o: $(BOOTLOADER) Makefile
	$(CC) $(CPPFLAGS) -DCNTFRQ=$(CNTFRQ) -DUART_BASE=$(UART_BASE) -DSYSREGS_BASE=$(SYSREGS_BASE) -DGIC_DIST_BASE=$(GIC_DIST_BASE) -DGIC_CPU_BASE=$(GIC_CPU_BASE) -c -o $@ $(BOOTLOADER)

model.lds: $(LD_SCRIPT) Makefile
	$(CC) $(CPPFLAGS) -DPHYS_OFFSET=$(PHYS_OFFSET) -DMBOX_OFFSET=$(MBOX_OFFSET) -DKERNEL_OFFSET=$(KERNEL_OFFSET) -DFDT_OFFSET=$(FDT_OFFSET) -DFS_OFFSET=$(FS_OFFSET) -DKERNEL=$(KERNEL) -DFILESYSTEM=$(FILESYSTEM) -DACPI=$(ACPI) -DACPI_OFFSET=$(ACPI_OFFSET) -E -P -C -o $@ $<

boot.xen.o: $(BOOTLOADER) Makefile
	$(CC) $(CPPFLAGS) -DCNTFRQ=$(CNTFRQ) -DUART_BASE=$(UART_BASE) -DSYSREGS_BASE=$(SYSREGS_BASE) -DGIC_DIST_BASE=$(GIC_DIST_BASE) -DGIC_CPU_BASE=$(GIC_CPU_BASE) -c -o $@ $(BOOTLOADER) -DXEN

model.xen.lds: $(LD_SCRIPT) Makefile
	$(CC) $(CPPFLAGS) -DPHYS_OFFSET=$(PHYS_OFFSET) -DMBOX_OFFSET=$(MBOX_OFFSET) -DBOOT=boot.xen.o -DXEN_OFFSET=$(XEN_OFFSET) -DKERNEL_OFFSET=$(KERNEL_OFFSET) -DFDT_OFFSET=$(FDT_OFFSET) -DFS_OFFSET=$(FS_OFFSET) -DXEN=$(XEN) -DKERNEL=$(KERNEL) -DFILESYSTEM=$(FILESYSTEM) -DACPI=$(ACPI) -DACPI_OFFSET=$(ACPI_OFFSET) -E -P -C -o $@ $<

ifeq ($(BUILD_DTB),y)
ifeq ($(DTC),)
	$(error No dtc found! You can git clone from git://git.jdl.com/software/dtc.git)
endif

fdt.dtb: $(FDT_DEPS) Makefile
	( echo "/include/ \"$(FDT_SRC)\"" ; echo "/ { $(CHOSEN_NODE) };" ) | tee chosen.dts | $(DTC) -O dtb -o $@ -
endif

# The filesystem archive might not exist if INITRD is not being used
.PHONY: all clean $(FILESYSTEM)
