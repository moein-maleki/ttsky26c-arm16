"""pytest: encoder, image loading and golden-model semantics (sprint plan, task 1)."""

import arm16_asm


def test_encode_known_words():
    assert arm16_asm.encode("MOV", "r0, #20") == 0xE3A00014
