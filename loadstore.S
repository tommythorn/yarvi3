        .globl  _start
_start: // First test if loading and storing works at all
        li      x2, 4
        lw      x9, 0(x2)
        nop

        li      x1, 42
        sw      x1, 0(x2)
        nop
        nop
        lw      x3, 0(x2)
        nop
        nop
        mv      x9, x3

        // Does bypassing work?
        li      x9, 666
        lw      x3, 0(x2)
        nop
        mv      x9, x3
        nop

        li      x1, 13
        sw      x1, 0(x2)
        li      x9, 11
        nop
        lw      x3, 0(x2)
        mv      x9, x3
        nop

        // Does bypassing stores work?
        li      x1, 55
        sw      x1, 0(x2)
        nop
        lw      x3, 0(x2)
        nop

        li      x1, 56
        sw      x1, 0(x2)
        lw      x3, 0(x2)
        nop
