/*
20210922 Complex pipelines aren't helped by Silice.

We need to leverage the Pipeline Control Invariant: For all stages
up-to and including the Controlling Stage, if a stage is valid, then
all *younger* stages are guaranteed to be valid as well.  Thus, as
long as we are only checking in the Controlling Stage, we only need to
worry about the validity of ourselves.  It also implies a benefit to
moving the Controlling Stage as far down in the pipeline as possible.
Also, this means we cannot insert invalid stages in the middle, so if
we introduce bubbles, they have to be well-formed nop instructions
(but marked as bubbles so they don't count in INSTRET, get allocated
in the ROB, etc).

In thinking about this, it seems to me that the valid signal is
actually more complicated than the token approach I used.

This still doesn't avoid the complications from bypassing from a load
further down in the pipeline.  We could of course move load up higher
by moving EX lower....
*/


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

// RISC-V Opcodes
$$LOAD          = 0;
//$$LOAD_FP     = 1;
//$$CUSTOM0     = 2;
//$$MISC_MEM    = 3;
$$OP_IMM        = 4;
//$$AUIPC         = 5;
//$$OP_IMM_32   = 6;
//$$EXT0        = 7;
$$STORE         = 8;
//$$STORE_FP    = 9;
//$$CUSTOM1     = 10;
//$$AMO         = 11;
$$OP            = 12;
//$$LUI           = 13;
//$$OP_32       = 14;
//$$EXT1        = 15;
//$$MADD        = 16;
//$$MSUB        = 17;
//$$NMSUB       = 18;
//$$NMADD       = 19;
//$$OP_FP       = 20;
//$$RES1        = 21;
//$$CUSTOM2     = 22;
//$$EXT2        = 23;
$$BRANCH        = 24;
$$JALR          = 25;
//$$RES0        = 26;
$$JAL           = 27;
//$$SYSTEM        = 28;
$$RES2          = 29;
//$$CUSTOM3     = 30;
//$$EXT3        = 31;



algorithm main(output uint8 leds)
{
  // Memory
//bram uint32 dcache[65536] = { 666, 777, 888, pad(999) }; // 256 KiB L1 = 64 Kb 32-bit words
  bram uint32 dcache[$DCACHE_WORDS$] = uninitialized;
  bram uint32 code[64] = {
$include('code.hex')
      pad(0)
  };

  // Architectural state
  simple_dualport_bram uint32 rf1[32] = {0,1,1,0,100,0,1,pad(0)};
  simple_dualport_bram uint32 rf2[32] = {0,1,1,0,100,0,1,pad(0)};

  uint32 cycle         = -1;    // track cycles (≡ CSR mcycle)
  uint32 seqno         = -1;    // track instructions (~ CSR minstret)
  uint32 pc            = uninitialized;

  uint1  restart       = 1;
  uint32 restart_pc    = 32h0;

  // Forward Flowing Pipeline Registers
  // .. IF
  uint1  restarting    = 0;
  uint32 pc_plus_4     = uninitialized;

  // .. DE
  uint32 insn          = uninitialized;
  uint5  opcode        = uninitialized;
  uint1  writes_reg    = uninitialized;
  uint32 branch_target = uninitialized;
  uint32 immediate     = uninitialized;
  uint1  BLT           = uninitialized;
  uint1  op2_is_imm    = uninitialized;
  uint6  wbr           = uninitialized;
  uint6  wbr_1         = uninitialized;
  uint6  wbr_2         = uninitialized;
  uint6  is_load       = uninitialized;
  uint6  is_load_1     = uninitialized;
  uint2  op1_src       = uninitialized;
  uint2  op2_src       = uninitialized;

  // .. EX
  uint32 op1           = uninitialized;
  uint32 op2           = uninitialized;
  uint32 op2_imm       = uninitialized;
  uint32 alu_result    = uninitialized; // loops

  // ... CM
  uint1  valid         = uninitialized;
  uint1  illegal       = uninitialized;

  // State Machine
  uint1  flushing      = 1;

  // Using Wb and an always_after block allows us to abstract away
  // the fact that RF is two idential blockrams.
  Wb     writeback;
  always_after {
    rf1.wenable1 = writeback.en;     rf2.wenable1 = writeback.en;
    rf1.addr1    = writeback.rd;     rf2.addr1    = writeback.rd;
    rf1.wdata1   = writeback_val;    rf2.wdata1   = writeback.val;
  }

  while (1) {
    {
      // ** FETCH STAGE **

      cycle         = cycle + 1;
      seqno         = seqno + 1;
      pc_plus_4     = pc + 4;
      pc            = restart ? restart_pc : pc_plus_4;
      code.addr     = pc[2,30];
      restarting    = restart;

    } -> {
      // ** DECODE AND REGISTER FETCH **

      insn          = code.rdata;
      opcode        = Rtype(insn).c == 3 ? Rtype(insn).opcode : 5d$RES2$;
      rf1.addr0     = Rtype(insn).rs1;
      rf2.addr0     = Rtype(insn).rs2;
      writes_reg    = Rtype(insn).rd != 0
                   && (opcode == $LOAD$
                    || opcode == $OP_IMM$
                    || opcode == $OP$
                    || opcode == $JALR$
                    || opcode == $JAL$);
      op2_is_imm    = opcode == $OP_IMM$
                   || opcode == $LOAD$
                   || opcode == $STORE$;

      if (restarting) {
          wbr_2     = 63;
          wbr_1     = 63;
      } else {
          wbr_2     = wbr_1;
          wbr_1     = wbr;
      }
      wbr           = {!writes_reg,Rtype(insn).rd};

      is_load_1     = is_load;
      is_load       = opcode == $LOAD$;

      op1_src       = (wbr_1 == Rtype(insn).rs1 && is_load_1)  ? 0 :
                      (wbr_1 == Rtype(insn).rs1)               ? 1 :
                      (wbr_2 == Rtype(insn).rs1)               ? 2 :
                                                                 3;
      op2_src       = (wbr_1 == Rtype(insn).rs2 && is_load_1)  ? 0 :
                      (wbr_1 == Rtype(insn).rs2)               ? 1 :
                      (wbr_2 == Rtype(insn).rs2)               ? 2 :
                                                                 3;

      immediate     = {{20{Btype(insn).i12}},
                       opcode == $LOAD$ || opcode == $OP_IMM$
                       ? Itype(insn).i11_0 : {Stype(insn).i11_5, Stype(insn).i4_0}};

      branch_target = pc + {{20{Btype(insn).i12}},
                                Btype(insn).i11,
                                Btype(insn).i10_5,
                                Btype(insn).i4_1,
                                1b0};

      BLT           = opcode == $BRANCH$ && Btype(insn).fun3 == 4;

    } -> {
      // ** EXECUTE STAGE **

      switch (op1_src) {
      case 0: {op1 = 1 ? dcache.rdata : writeback.val ;} // 0 to disable load->use bypass
      case 1: {op1 = alu_result   ;}
      case 2: {op1 = writeback.val;}
      case 3: {op1 = rf1.rdata0   ;}
      }

      switch (op2_src) {
      case 0: {op2 = 1 ? dcache.rdata : writeback.val ;} // 0 to disable load->use bypass
      case 1: {op2 = alu_result   ;}
      case 2: {op2 = writeback.val;}
      case 3: {op2 = rf2.rdata0   ;}
      }

      op2_imm       = op2_is_imm ? immediate : op2;

      alu_result    = op1 + op2_imm;

      dcache.addr   = (1 ? (op1 + immediate) : rf1.rdata0) >> 2; // 0 to disable alu->load
      dcache.wdata  = op2;
      dcache.wenable= valid && opcode == $STORE$;

    } -> {
      // ** COMMIT **

      valid         = restarting | !flushing;

      writeback.rd  = Rtype(insn).rd;
      writeback.val = is_load ? dcache.rdata : alu_result;
      writeback.en  = valid && writes_reg;

      if (valid && writeback.en) {
          leds = writeback_val;
      }

      restart       = valid && BLT && op1 < op2;
      restart_pc    = branch_target;

      illegal       = valid && insn[0,2] != 3;

      if (valid) {
          flushing = restart;
      }

$$if SIMULATION then
      if (valid) {
        switch (opcode) {
        case $LOAD$: {
          if (immediate == 0) {
             $display("%5d WB %h:%h x%1d = *(u32 *)x%1d  \t// %1d", cycle, pc, insn,
                      Rtype(insn).rd, Rtype(insn).rs1, writeback.val);
          } else {
             $display("%5d WB %h:%h x%1d = *(u32 *)(x%1d + %1d)  \t// %1d", cycle, pc, insn,
                      Rtype(insn).rd, Rtype(insn).rs1, immediate, writeback.val);
          }}
        case $STORE$: {
          if (immediate == 0) {
             $display("%5d WB %h:%h *(u32 *)x%1d = x%1d", cycle, pc, insn,
                      Rtype(insn).rs1, Rtype(insn).rs2);
          } else {
             $display("%5d WB %h:%h *(u32 *)(x%1d + %1d) = x%1d", cycle, pc, insn,
                      Rtype(insn).rs1, immediate, Rtype(insn).rs2);
          }}
        case $OP$: {
          $display("%5d WB %h:%h x%1d = x%1d + x%1d   \t// %1d", cycle, pc, insn,
                   Rtype(insn).rd, Rtype(insn).rs1, Rtype(insn).rs2, writeback.val);
          }
        case $OP_IMM$: {
          if (Rtype(insn).rs1 == 0 && Rtype(insn).rd == 0 && immediate == 0) {
            $display("%5d WB %h:%h", cycle, pc, insn);
          } else {
            if (Rtype(insn).rs1 == 0) {
              $display("%5d WB %h:%h x%1d = %1d", cycle, pc, insn,
                       Rtype(insn).rd, immediate);
            } else {
              if (immediate == 0) {
                 $display("%5d WB %h:%h x%1d = x%1d   \t\t// %1d", cycle, pc, insn,
                          Rtype(insn).rd, Rtype(insn).rs1, writeback.val);
              } else {
                 $display("%5d WB %h:%h x%1d = x%1d + %1d   \t// %1d", cycle, pc, insn,
                          Rtype(insn).rd, Rtype(insn).rs1, immediate, writeback.val);
              }
            }
          }
        }
        case $BRANCH$: {
          $display("%5d WB %h:%h if x%1d < x%1d: pc = %h", cycle, pc, insn,
                   Rtype(insn).rs1, Rtype(insn).rs2, branch_target);
        }

        default: {
          if (writeback.en) {
            $display("%5d WB %h:%h %1d,%1d   %d -> r%1d", cycle,
                      pc, insn, op2, op1, writeback.val, writeback.rd);
          } else {
            $display("%5d WB %h:%h %1d,%1d", cycle, pc, insn, op2, op1);
          }
        }}
      }
$$end
    }

    if (illegal) { break; }
  }
}
