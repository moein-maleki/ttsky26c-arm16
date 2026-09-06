MOV r0, #0
    MOV r10, #0
    MOV r1, #0xFF00
loop:
    ADD r2, r0, #1
    ADD r3, r2, #1
    ADD r4, r3, #1
    ADD r5, r4, #1
    ADD r6, r5, #1
    ADD r7, r6, #1
    ADD r8, r7, #1
    SUB r0, r8, #6
    CMP r0, #0
    ADDEQ r10, r10, #1
    STR r10, [r1, #0]
    B loop
    B .
