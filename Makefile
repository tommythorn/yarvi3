SHELL=/bin/bash
TARGET=verilator
CODE=loadstore.hex
BUILD=/tmp/BUILD_yarvi3
DCACHE_WAY_SZ_LOG2=12 # 2^12 words = 2^14 bytes = 16 KiB => 32 KiB D$
OPTS=-D DCACHE_WAY_SZ_LOG2=$(DCACHE_WAY_SZ_LOG2)
#RISCVGCC=riscv64-linux-gnu-
RISCVGCC=riscv64-elf-
OD=god

all: yarvi3

yarvi3:
	rm -rf $(BUILD)
	$(MAKE) $(CODE)
	-@cp $(CODE) code.hex
	silice-make.py $(OPTS) -s $@.ice -b $(TARGET) -p basic -t shell -o $(BUILD)

%.o: %.S
	$(RISCVGCC)gcc -fno-builtin -march=rv32i -mabi=ilp32 -Ofast -c $< -o $@

%.bin: %.elf
	$(RISCVGCC)objcopy -O binary $< $@

%.hex: %.bin
	$(OD) -t x4 -An -w4 -v $< | xargs -n1 printf "   32h%s,\n" > $@

%.elf: %.o
	$(RISCVGCC)ld  -m elf32lriscv -b elf32-littleriscv -Ttext=0 $< -o $@

%.dis: %.elf
	$(RISCVGCC)objdump -d -M numeric,no-aliases $< > $@

clean:
	rm -rf /tmp/BUILD_*

hardware:
	$(MAKE) TARGET=ulx3s
