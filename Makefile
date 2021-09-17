TARGET=verilator

all: yarvi3

.DEFAULT: $@.ice.lpp
		silice-make.py -s $@.ice -b $(TARGET) -p basic -t shell -o /tmp/BUILD_$(subst :,_,$@)

%.o: %.S
	riscv64-linux-gnu-gcc -fno-builtin -march=rv32i -mabi=ilp32 -Ofast -c $< -o $@

%.elf: %.o
	riscv64-linux-gnu-ld  -m elf32lriscv -b elf32-littleriscv -Ttext=0 $< -o $@

%.dis: %.elf
	riscv64-linux-gnu-objdump -d -M numeric,no-aliases $< > $@

clean:
	rm -rf /tmp/BUILD_*

hardware:
	$(MAKE) TARGET=ulx3s
