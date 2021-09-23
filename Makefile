TARGET=verilator
CODE=fib.hex

all: yarvi3

code.hex: $(CODE)
	cp $< $@

.DEFAULT: $@.ice.lpp
	make code.hex
	silice-make.py -s $@.ice -b $(TARGET) -p basic -t shell -o /tmp/BUILD_$(subst :,_,$@)

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
