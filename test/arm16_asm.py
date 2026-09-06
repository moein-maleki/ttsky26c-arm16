"""arm16 encoder, image builder and reference decoder for the instruction subset of docs/spec.md 3.1.

Software testbench, task 1 of the sprint plan. Written from the ARM architecture definition."""


class AsmError(Exception):
    """Raised for any source outside the supported subset."""


def assemble(source, origin=0):
    """Assemble a program text into a list of 32-bit words, labels resolved."""
    raise NotImplementedError


def encode(mnemonic, operands, cond="AL", pc=0, labels=None):
    """Encode one instruction and return its 32-bit word."""
    raise NotImplementedError


def build_flash_image(words, size=32768):
    """Return a little-endian byte image with word i at byte offset 4 * i."""
    raise NotImplementedError


def decode(word):
    """Reference decoder: return a dict describing the instruction fields and class."""
    raise NotImplementedError
