int _start() {
    int r5 = 0;
    int r6 = 1;
    int r1 = 1;
    int r2 = 1;
    int r3;
    int r4 = 250;

    do {
        r5 = r5 + r6;
        r3 = r1 + r2;
        r1 = r2;
        r2 = r3;
    } while (r3 < r4);

    asm volatile("" :: "r" (r5));

    return r3;
}
