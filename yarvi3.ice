algorithm main(output uint8 leds)
{
    dualport_bram uint32 rf0[32] = {0,1,1,0,100,0,1,pad(0)};
    dualport_bram uint32 rf1[32] = {0,1,1,0,100,0,1,pad(0)};

    // A add, B blt
    bram uint32 code[32] = {
        32h0A556,  // r5, r5, r6

        32h0A312,  // r3 = r1 + r2
        32h0A120,  // r1 = r2
        32h0A230,  // r2 = r3
        32h0B034,  // if r3 < r4: pc = 0

        pad(0),
    };

    uint32 cycle = 0;

    uint1  restart = 1;
    uint1  restart_token = uninitialized;
    uint1  flushing = 1;
    uint1  valid = uninitialized;
    uint32 restart_pc = 0;

    uint32 pc = uninitialized;
    uint32 insn = uninitialized;
    int4   insn_r0 = uninitialized;
    int4   insn_r1 = uninitialized;
    int4   insn_rd = uninitialized;
    int4   insn_opcode = uninitialized;
    uint32 insn_brtarget = uninitialized;

    uint32 r0_value = uninitialized;
    uint32 r1_value = uninitialized;
    uint1  writeback_enable = 0;
    uint8  writeback_regno = uninitialized;
    uint32 writeback_value = uninitialized;

    code.wenable = 0;
    code.wdata = 0;
    rf0.wenable0 = 0;
    rf0.wenable1 = 0;
    rf1.wenable0 = 0;
    rf1.wenable1 = 0;

    while (cycle < 80) {
        cycle = cycle + 1;

        {

            pc = restart ? restart_pc : pc + 32h1;
            restart_token = restart;
            code.addr = pc;

        } -> {

            insn = code.rdata;
            insn_r0 = insn[0, 4];
            insn_r1 = insn[4, 4];
            insn_rd = insn[8, 4];
            insn_opcode = insn[12, 4];
            insn_brtarget = insn[16,16];

            rf0.addr0 = insn_r0;
            rf1.addr0 = insn_r1;

        } -> {

            valid = restart_token | !flushing;

            r0_value = (writeback_enable && writeback_regno == insn_r0) ? writeback_value : rf0.rdata0;
            r1_value = (writeback_enable && writeback_regno == insn_r1) ? writeback_value : rf1.rdata0;

            restart = valid && insn_opcode == 4hB && r1_value < r0_value;
            restart_pc = insn_brtarget;

            writeback_enable = valid && insn_opcode == 4hA && insn_rd != 4h0;
            writeback_regno = insn_rd;
            writeback_value = r0_value + r1_value;

            rf0.wenable1 = writeback_enable;
            rf0.addr1 = writeback_regno;
            rf0.wdata1 = writeback_value;
            rf1.wenable1 = writeback_enable;
            rf1.addr1 = writeback_regno;
            rf1.wdata1 = writeback_value;

            if (valid) {
                flushing = restart;
            }

        } -> {

            if (valid) {
                if (writeback_enable) {
                    $display("%05d WB %h:%h %d,%d   %d -> r%1d", cycle,
                             pc, insn, r1_value, r0_value, writeback_value,
                             writeback_regno);
                } else {
                    $display("%05d WB %h:%h %d,%d", cycle,
                             pc, insn, r1_value, r0_value);
                }
            }

        }
    }
}
