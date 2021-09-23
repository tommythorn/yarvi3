/*
 * YARVI3 - Yet Another RISC-V Implementation, 3rd generation
 *
 * With thanks to Sylvain Lefevbre for helpful Silice suggestions.
 *
 * Copyright Tommy Thorn, 2021
 * MIT license, see LICENSE_MIT somewhere
 */

// Coding style exception: these lines are a direct mapping on the
// RISC-V specification and really are more readable as long lines.
// Shortened immXX to iXX, funct to fun
bitfield Rtype {uint7  fun7,             uint5 rs2, uint5 rs1, uint3 fun3, uint5 rd,              uint5 opcode, uint2 c}
bitfield Itype {uint12 i11_0,                       uint5 rs1, uint3 fun3, uint5 rd,              uint5 opcode, uint2 c}
bitfield Stype {uint7  i11_5,            uint5 rs2, uint5 rs1, uint3 fun3, uint5 i4_0,            uint5 opcode, uint2 c}
bitfield Btype {uint1  i12, uint6 i10_5, uint5 rs2, uint5 rs1, uint3 fun3, uint4 i4_1, uint1 i11, uint5 opcode, uint2 c}
bitfield Utype {uint20 i31_12,                                             uint5 rd,              uint5 opcode, uint2 c}
bitfield Jtype {uint1  i20, uint10 i10_1, uint1 i11, uint8 i19_12,         uint5 rd,              uint5 opcode, uint2 c}

// a group for writeback
group Wb { uint1 en = 0, uint4 rd = uninitialized, uint32 val = uninitialized }

algorithm main(output uint8 leds)
{
  // Architectural state
  bram uint32 code[32] = {
      32h006282b3,           // add     x5,x5,x6
      32h002081b3,           // add     x3,x1,x2
      32h000100b3,           // add     x1,x2,x0
      32h00018133,           // add     x2,x3,x0
      32hfe41c8e3,           // blt     x3,x4,0 <_start>
      32h00000033,           // add     x0,x0,x0
      32h00000033,           // add     x0,x0,x0
      32h00000033,           // add     x0,x0,x0
      32h00000033,           // add     x0,x0,x0
      32h00000033,           // add     x0,x0,x0
      pad(0),
  };

  simple_dualport_bram uint32 rf0[32] = {0,1,1,0,100,0,1,pad(0)};
  simple_dualport_bram uint32 rf1[32] = {0,1,1,0,100,0,1,pad(0)};

  uint32 cycle         = -1;    // track cycles (= CSR mcycles)
  uint32 seqno         = -1;    // track instructions (= CSR minstret)
  uint32 pc            = uninitialized;

  // Pipeline registers
  uint1  restart       = 1;
  uint32 restart_pc    = 32h0;
  uint1  valid         = uninitialized;

  uint32 insn          = uninitialized;
  uint1  writes_reg    = uninitialized;
  uint32 branch_target = uninitialized;
  uint1  BLT           = uninitialized;

  uint32 rs1_value     = uninitialized;
  uint32 rs2_value     = uninitialized;

  Wb     writeback;

  always_after {
    // Using Wb and an always_after block allows us to abstract away
    // the fact that RF is two idential blockrams.
    rf0.wenable1 = writeback.en;     rf1.wenable1 = writeback.en;
    rf0.addr1    = writeback.rd;     rf1.addr1    = writeback.rd;
    rf0.wdata1   = writeback_val;    rf1.wdata1   = writeback.val;
  }

$$if SIMULATION then
  while (cycle != 80) {
$$else
  while (1) {
$$end

    {
      // Fetch stage

      cycle         = cycle + 1;
      seqno         = seqno + 1;
      pc            = restart ? restart_pc : pc + 4;
      code.addr     = pc[2,30];
      valid         = 1;

    } -> {
      // Decode and register fetch
      //  LOAD,   LOAD_FP,  CUSTOM0, MISC_MEM, OP_IMM, AUIPC, OP_IMM_32, EXT0,
      //  STORE,  STORE_FP, CUSTOM1, AMO,      OP,     LUI,   OP_32,     EXT1,
      //  MADD,   MSUB,     NMSUB,   NMADD,    OP_FP,  RES1,  CUSTOM2,   EXT2,
      //  BRANCH, JALR,     RES0,    JAL,      SYSTEM, RES2,  CUSTOM3,   EXT3,

      valid         = valid & ~restart;
      insn          = code.rdata;
      rf0.addr0     = Rtype(insn).rs1;
      rf1.addr0     = Rtype(insn).rs2;
      writes_reg    = Rtype(insn).rd != 0
                   && (Rtype(insn).opcode == /* LOAD   */  0
                    || Rtype(insn).opcode == /* OP_IMM */  4
                    || Rtype(insn).opcode == /* OP     */ 12
                    || Rtype(insn).opcode == /* JALR   */ 25
                    || Rtype(insn).opcode == /* JAL    */ 27);

      branch_target = pc + {{20{Btype(insn).i12}},
                                Btype(insn).i11,
                                Btype(insn).i10_5,
                                Btype(insn).i4_1,
                                1b0};
      BLT = Rtype(insn).opcode == 24 && Btype(insn).fun3 == 4;

    } -> {
      // Execute stage

      valid         = valid & ~restart;
      rs1_value     = writeback.en && writeback.rd == Rtype(insn).rs1
                    ? writeback.val : rf0.rdata0;
      rs2_value     = writeback.en && writeback.rd == Rtype(insn).rs2
                    ? writeback.val : rf1.rdata0;
      writeback.en  = valid && writes_reg;
      writeback.rd  = Rtype(insn).rd;
      writeback.val = rs1_value + rs2_value;
      restart       = valid && BLT && rs1_value < rs2_value;
      restart_pc    = branch_target;

    } -> {
      // Commit

      if (valid && writeback.en) {
          leds = writeback_val;
      }

  $$if SIMULATION then
      if (valid) {
        if (writeback.en) {
          $display("%05d WB %h:%h %d,%d   %d -> r%1d", cycle,
                    pc, insn, rs2_value, rs1_value, writeback.val, writeback.rd);
        } else {
          $display("%05d WB %h:%h %d,%d", cycle, pc, insn, rs2_value, rs1_value);
        }
      }
  $$end

    }
  }
}
