	.globl	_start
_start:	add	x5, x5, x6
	add	x3, x1, x2
	add	x1, x2, x0
	add	x2, x3, x0
	blt	x3, x4, _start

        add	x0, x0, x0
        add	x0, x0, x0
        add	x0, x0, x0
        add	x0, x0, x0
        add	x0, x0, x0
