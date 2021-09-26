SHELL=/bin/bash
TARGET=verilator
CODE=loadstore.hex
BUILD=/tmp/BUILD_yarvi3
DCACHE_WORDS=1024
OPTS=-D DCACHE_WORDS=$(DCACHE_WORDS)

all: yarvi3

yarvi3:
	rm -rf $(BUILD)
	$(MAKE) $(CODE)
	-@cp $(CODE) code.hex
	silice-make.py $(OPTS) -s $@.ice -b $(TARGET) -p basic -t shell -o $(BUILD)

%.o: %.S
	riscv64-linux-gnu-gcc -fno-builtin -march=rv32i -mabi=ilp32 -Ofast -c $< -o $@

%.bin: %.elf
	riscv64-linux-gnu-objcopy -O binary $< $@

%.hex: %.bin
	od -t x4 -An -w4 -v $< | xargs -n1 printf "   32h%s,\n" > $@

%.elf: %.o
	riscv64-linux-gnu-ld  -m elf32lriscv -b elf32-littleriscv -Ttext=0 $< -o $@

%.dis: %.elf
	riscv64-linux-gnu-objdump -d -M numeric,no-aliases $< > $@

clean:
	rm -rf /tmp/BUILD_*

hardware:
	$(MAKE) TARGET=ulx3s
