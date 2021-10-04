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
group Wb { uint1 en = 0, uint6 rd = uninitialized, uint32 val = uninitialized }

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
// XXX strawman: 4 GiB PA = 32 bits => 18 tags for a 16 KiB way
  bram uint18 dcache0_tag[$1 << (DCACHE_WAY_SZ_LOG2 - 6)$] = { pad(0) };
  bram uint18 dcache1_tag[$1 << (DCACHE_WAY_SZ_LOG2 - 6)$] = { pad(0) };
  bram uint32 dcache0[$1 << (DCACHE_WAY_SZ_LOG2 - 2)$] = uninitialized;
  bram uint32 dcache1[$1 << (DCACHE_WAY_SZ_LOG2 - 2)$] = uninitialized;
  bram uint32 code[64] = {
$include('code.hex')
      pad(0)
  };

  // Architectural state
  simple_dualport_bram uint32 prf1[64] = {pad(0)};
  simple_dualport_bram uint32 prf2[64] = {pad(0)};

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

  // .. RE
  uint6 rmap[32]       = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31};
  uint5 rfreelist_w    = 32;
  uint5 rfreelist_r    = 0;

  uint6 map[32]        = uninitialized;
  uint6 freelist[32]   = {32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63};
  uint5 freelist_r     = uninitialized;
  uint5 freelist_r_real= uninitialized;
  uint6 pr1            = uninitialized;
  uint6 pr2            = uninitialized;
  uint6 prd            = uninitialized;
  uint6 prd_old        = uninitialized;

  // .. EX
  uint32 op1           = uninitialized;
  uint32 op2           = uninitialized;
  uint32 op2_imm       = uninitialized;
  uint32 alu_result    = uninitialized; // loops

  uint32 dcache_rdata  = uninitialized; // loops
  uint1  tag0_match    = uninitialized;
  uint1  tag1_match    = uninitialized;
  uint1  cache_miss    = uninitialized;

  uint32 pending_store_addr = uninitialized;
  uint32 pending_store_data = uninitialized;
  uint1  pending_store_wen0 = 0;
  uint1  pending_store_wen1 = 0;

  // ... CM
  uint1  valid         = uninitialized;
  uint1  illegal       = uninitialized;

  // State Machine
  uint1  flushing      = 1;

  // Using Wb and an always_after block allows us to abstract away
  // the fact that RF is two idential blockrams.
  Wb     writeback;
  always_after {
    prf1.wenable1 = writeback.en;     prf2.wenable1 = writeback.en;
    prf1.addr1    = writeback.rd;     prf2.addr1    = writeback.rd;
    prf1.wdata1   = writeback_val;    prf2.wdata1   = writeback.val;
    dcache_rdata  = dcache0_tag.rdata == alu_result[$DCACHE_WAY_SZ_LOG2$, 18]
                  ? dcache0.rdata : dcache1.rdata;
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
      // ** RENAMING **

      /* XXX A slight Silice wart; it can't grok the same variable
       * updated multiple times in multiple places so we SSA convert
       * it and introduce freelist_r_real */
      // XXX ugly, find a better way
      freelist_r_real = restarting ? rfreelist_r : freelist_r;
      if (restarting) {
      // XXX This is a likely critical-path: we effectively do
      //   prX = restarting ? rmap[...rsX] : map[...rsX];
      // it _could_ help making that explicit.
$$for i=1,31 do
         map[$i$] = rmap[$i$];
$$end
      }

      pr1                 = map[Rtype(insn).rs1];
      pr2                 = map[Rtype(insn).rs2];
      prd_old             = map[Rtype(insn).rd];
      prd                 = freelist[freelist_r_real];
      map[Rtype(insn).rd] = prd;

      prf1.addr0          = pr1;
      prf2.addr0          = pr2;
      freelist_r          = freelist_r_real + writes_reg;

    } -> {
      // ** EXECUTE STAGE **
      switch (op1_src) {
      case 0: {op1 = dcache_rdata ;}
      case 1: {op1 = alu_result   ;}
      case 2: {op1 = writeback.val;}
      case 3: {op1 = prf1.rdata0  ;}
      }

      switch (op2_src) {
      case 0: {op2 = dcache_rdata ;}
      case 1: {op2 = alu_result   ;}
      case 2: {op2 = writeback.val;}
      case 3: {op2 = prf2.rdata0  ;}
      }

      // XXX This doesn't seem to make sense.  Why not fold this into
      // the bypass? (We'll need two as we need both op2 and op2_imm)
      op2_imm          = op2_is_imm ? immediate : op2;

      alu_result       = op1 + op2_imm;

      dcache0_tag.addr = (op1 + immediate) >> 6;
      dcache1_tag.addr = (op1 + immediate) >> 6;

      dcache0.addr     = opcode == $LOAD$
                       ? (op1 + immediate) >> 2 : pending_store_addr;
      dcache1.addr     = opcode == $LOAD$
                       ? (op1 + immediate) >> 2 : pending_store_addr;
      dcache0.wdata    = pending_store_data;
      dcache1.wdata    = pending_store_data;
      dcache0.wenable  = pending_store_wen0 && opcode != $LOAD$;
      dcache1.wenable  = pending_store_wen1 && opcode != $LOAD$;

    } -> {
      // ** COMMIT **

      tag0_match       = dcache0_tag.rdata == alu_result[$DCACHE_WAY_SZ_LOG2$, 18];
      tag1_match       = dcache1_tag.rdata == alu_result[$DCACHE_WAY_SZ_LOG2$, 18];
      cache_miss       = !tag0_match & !tag1_match
                       & (opcode == $LOAD$ || opcode == $STORE$);

      if (cache_miss) {
        $display("%h miss", alu_result);
      }

      valid            = (restarting | !flushing) & !cache_miss;

      if (valid && opcode == $LOAD$ &&
          (pending_store_wen0 || pending_store_wen1) &&
          pending_store_addr == dcache0.addr) {
        $display("load-hit-store, restart %h", pc);
        valid        = 0;
        restart      = 1;
        restart_pc   = pc;
        flushing     = 1;
      } else {
        restart      = valid && BLT && op1 < op2;
        restart_pc   = branch_target;
      }

      if (valid && opcode == $STORE$) {
        pending_store_data = op2;
        pending_store_addr = (op1 + immediate) >> 2;
        pending_store_wen0 = dcache0_tag.rdata == alu_result[$DCACHE_WAY_SZ_LOG2$, 18];
        pending_store_wen1 = dcache1_tag.rdata == alu_result[$DCACHE_WAY_SZ_LOG2$, 18];
      } else {
        pending_store_wen0 = 0;
        pending_store_wen1 = 0;
      }

      writeback.rd  = prd;
      writeback.val = is_load ? dcache_rdata : alu_result;
      writeback.en  = valid && writes_reg;

      if (writeback.en) {
        leds                  = writeback_val;

        rmap[Rtype(insn).rd]  = prd;
        freelist[rfreelist_w] = prd_old;
        rfreelist_w           = rfreelist_w + 1;
        rfreelist_r           = freelist_r;
      }

      illegal       = valid && insn[0,2] != 3; // XXX we already remapped that

      if (valid) {
        flushing = restart;
      }

$$if SIMULATION then
      if (valid) {
        if (pending_store_wen0 | pending_store_wen1) {
          $display("pending store of %h to %h way%d", pending_store_data,
                   pending_store_addr, pending_store_wen1);
        }

        // Disassemble
        switch (opcode) {
          case $LOAD$: {
            if (immediate == 0) {
               $display("%5d WB %h:%h x%1dp%1d = *(u32 *)x%1dp%1d  \t// %1d", cycle, pc, insn,
                        Rtype(insn).rd, prd, Rtype(insn).rs1, pr1, writeback.val);
            } else {
               $display("%5d WB %h:%h x%1dp%1d = *(u32 *)(x%1dp%1d + %1d)  \t// %1d", cycle, pc, insn,
                        Rtype(insn).rd, prd, Rtype(insn).rs1, pr1, immediate, writeback.val);
            }
          }
          case $STORE$: {
            if (immediate == 0) {
               $display("%5d WB %h:%h *(u32 *)x%1dp%1d = x%1dp%1d", cycle, pc, insn,
                        Rtype(insn).rs1, pr1, Rtype(insn).rs2, pr2);
            } else {
               $display("%5d WB %h:%h *(u32 *)(x%1dp%1d + %1d) = x%1dp%1d", cycle, pc, insn,
                        Rtype(insn).rs1, pr1, immediate, Rtype(insn).rs2, pr2);
            }
          }
          case $OP$: {
            $display("%5d WB %h:%h x%1dp%1d = x%1dp%1d + x%1dp%1d   \t// %1d", cycle, pc, insn,
                     Rtype(insn).rd, prd, Rtype(insn).rs1, pr1, Rtype(insn).rs2, pr2, writeback.val);
          }
          case $OP_IMM$: {
            if (Rtype(insn).rs1 == 0 && Rtype(insn).rd == 0 && immediate == 0) {
              $display("%5d WB %h:%h", cycle, pc, insn);
            } else {
              if (Rtype(insn).rs1 == 0) {
                $display("%5d WB %h:%h x%1dp%1d = %1d", cycle, pc, insn,
                         Rtype(insn).rd, prd, immediate);
              } else {
                if (immediate == 0) {
                   $display("%5d WB %h:%h x%1dp%1d = x%1dp%1d   \t\t// %1d", cycle, pc, insn,
                            Rtype(insn).rd, prd, Rtype(insn).rs1, pr1, writeback.val);
                } else {
                   $display("%5d WB %h:%h x%1dp%1d = x%1dp%1d + %1d   \t// %1d", cycle, pc, insn,
                            Rtype(insn).rd, prd, Rtype(insn).rs1, pr1, immediate, writeback.val);
                }
              }
            }
          }
          case $BRANCH$: {
            $display("%5d WB %h:%h if x%1dp%1d < x%1dp%1d: pc = %h", cycle, pc, insn,
                     Rtype(insn).rs1, pr1, Rtype(insn).rs2, pr2, branch_target);
          }

          default: {
            if (writeback.en) {
              $display("%5d WB %h:%h %1d,%1d   %d -> r%1d", cycle,
                        pc, insn, op2, op1, writeback.val, writeback.rd);
            } else {
              $display("%5d WB %h:%h %1d,%1d", cycle, pc, insn, op2, op1);
            }
          }
        }
      }
$$end
    }

    if (illegal) {
      break;
    }
  }
}
