# The 3rd gen YARVI

[YARVI (Yet Another RISC-V Implementation, naming is
hard)](https://github.com/tommythorn/yarvi) was the first non-Berkeley
RISC-V softcore, originally release in 2014.  It was quite bare-bones.
The second generation (YARVI2) was a complete RV32IM, also in Verilog,
but the performance wasn't acceptable and it was never released.

Finding [Silice](https://github.com/sylefeb/silice) has inspired me to
try again, this time starting over in Silice.  The first steps is just
getting a trivial pipeline going.

# A four stage (ADD, BLT) pipeline with bypass and restart/flush

Due to a bug in Silice I couldn't annotate the pipeline stages, but
it's the classic Fetch, Decode/Reg Fetch, Execute, Writeback.

Only two RISC instructions are implemented, ADD and BLT.  The encoding
is chosen such that we can trivially write instructions direct in
hexidecimal.  Instructions are 32-bit.  Given an instruction `insn`,
`insn[31:16]` is the absolute branch target, `insn[15:12]` is the
opcode (4hA for ADD and 4hB for BLT), `insn[11:8]` is the destination
register (rd), `insn[7:4]` is registers rs, and `insn[3:0]` is rt.
(I'm actually fond of Silice's notation would write, say rd, as
`insn[8,4]` but I think it would have been clearer as `insn[8 :+ 4]`).

## Pipeline restarting/flushing

The most interesting aspect of this implementation is how flush is
handled.

Instead of the traditional valid bit in all stages that is cleared on
restart (a messy and error prone process), the stage that can restart
the pipeline (here Execute) has two-state state machine, Normal and
Flushing.  When it decides to restart the pipeline, it issues the
Restart signal to the head of the pipeline (Fetch) and enters
Flushing.  While in Flushing, it ignores everything incoming.  (For
efficiency reasons we only gate assignments that affects state, such
as register file writeback and the restart controls).

Once the restart signal has propagated back to Execute (captured in
"restart_token") it signals that everything has been flushed and we
should transition back to Normal.

## Lessons

This was my first Silice design and the pipeline mechanism wasn't
documented, but through trial and error, it turned out to be straight
forward.

Clearly this is cleaner, simpler, and less error prone the equivalent
Verilog implementation.  Notably,

  * there is no need to name the stage explicity (pipeline variables
    refer back to the previous stage unless it's redefined in the
    current)

  * pipeline variables are automatically propagated between stages

  * it's impossible to accidentally capture values from the wrong
    stage

Together this also means that inserting a stage in the middle requires
no changes to the other stages.
