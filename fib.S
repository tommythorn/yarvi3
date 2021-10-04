        .globl  _start
_start: li      x4, 2047        // limit
        li      x1, 1
        li      x2, 1
_loop:  add     x3, x1, x2
        mv      x1, x2
        mv      x2, x3          // 2 stage bypass
        blt     x3, x4, _loop   // 3 stage
