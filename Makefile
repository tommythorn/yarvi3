all: yarvi3

.DEFAULT: $@.ice.lpp
		silice-make.py -s $@.ice -b verilator -p basic -t shell -o /tmp/BUILD_$(subst :,_,$@)

clean:
	rm -rf /tmp/BUILD_*
