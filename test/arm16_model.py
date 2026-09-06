"""arm16 golden model: the instruction subset, the address map and the peripherals of docs/spec.md,
written from the ARM architecture definition and not from the RTL."""


class Arm16Model:
    def __init__(self, flash, boot_rom=None, fwd_en=True):
        raise NotImplementedError
