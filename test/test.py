"""arm16 cocotb suite (docs/spec.md 14.4). RTL-only tests use the 1,024-word test ROM (make ROMTEST=yes)
and read registers by hierarchy; flash-fed tests (task 4) use the memory models and the dump epilogue
and run at gate level too. Every DUT output is sampled 20 ns after the rising edge (mid-cycle), so the
same driver serves RTL and the gate-level netlist."""

import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

import arm16_asm as asm
import programs
from arm16_model import Arm16Model

GL = os.environ.get("GATES", "no") == "yes"
ROMTEST = os.environ.get("ROMTEST", "no") == "yes"
PERIOD_NS = 40
SAMPLE_NS = 20
ROM_WORDS = 1024


def dp(dut):
    return dut.user_project.arm16_datapath_unit


def ctl(dut):
    return dut.user_project.arm16_controller_unit


def pins(fwd_en=1, disp_sel=0, uart_en=0, uart_rx=1, dly=2, boot_rom=0, user=0):
    return (fwd_en | (disp_sel << 1) | (uart_en << 2) | (uart_rx << 3) | ((dly & 3) << 4)
            | (boot_rom << 6) | (user << 7))


async def mid_cycle(dut):
    await RisingEdge(dut.clk)
    await Timer(SAMPLE_NS, unit="ns")


def start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, PERIOD_NS, unit="ns").start())


async def reset_dut(dut, ui, rom_words=None, regs=None):
    """Hold reset, load the test ROM and the register pattern while the straps latch, release."""
    dut.ena.value = 1
    dut.ui_in.value = ui
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 3)
    if rom_words is not None:
        mem = dp(dut).demo_rom_unit.mem
        for i in range(ROM_WORDS):
            mem[i].value = rom_words[i] if i < len(rom_words) else 0xEAFFFFFE
    if regs is not None:
        rf = dp(dut).register_file_unit.regs
        for i, v in enumerate(regs):
            rf[i].value = v
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 3)


async def run_until_self_branch(dut, max_cycles=20000):
    """Run until a taken branch to its own address is in execute, then drain the pipeline."""
    d = dp(dut)
    for cycle in range(max_cycles):
        await mid_cycle(dut)
        if int(d.redirect_out.value) and int(d.ex_branch.value) and \
                int(d.ex_branch_target.value) == int(d.ex_pc.value):
            await ClockCycles(dut.clk, 6)
            return cycle
    raise AssertionError("the program did not reach its self-branch in %d cycles" % max_cycles)


def check_state(dut, model, regs=range(15), check_vga=True):
    d = dp(dut)
    for i in regs:
        got = int(d.register_file_unit.regs[i].value)
        exp = model.regs[i]
        assert got == exp, "r%d: dut 0x%04X model 0x%04X" % (i, got, exp)
    got_flags = int(d.nzcv.value)
    assert got_flags == model.flags_word(), "flags NZCV: dut %s model %s" % (
        format(got_flags, "04b"), format(model.flags_word(), "04b"))
    if check_vga:
        got = int(d.vga_val.value)
        assert got == model.vga_val, "VGA_VAL: dut 0x%04X model 0x%04X" % (got, model.vga_val)
        assert int(d.vga_fg.value) == model.vga_fg and int(d.vga_bg.value) == model.vga_bg


async def run_rom_program(dut, source, fwd_en=1, sw_extra=0, max_cycles=20000):
    """Assemble, run on the model in ROM mode and on the DUT from the test ROM, compare."""
    words = asm.assemble(source)
    assert len(words) <= ROM_WORDS
    ui = pins(fwd_en=fwd_en, boot_rom=1) | sw_extra
    model = Arm16Model(b"", boot_rom=words + [0xEAFFFFFE] * (ROM_WORDS - len(words)), fwd_en=bool(fwd_en), sw=ui)
    steps = model.run(max_instr=max_cycles)
    assert steps < max_cycles, "the model did not stop"
    await reset_dut(dut, ui, rom_words=words, regs=list(model.__class__(b"", boot_rom=[0]).regs))
    cycles = await run_until_self_branch(dut, max_cycles)
    check_state(dut, model)
    return cycles, steps, model


# ------------------------------------------------------------------------------------------- directed
def make_directed(name, fwd_en):
    async def body(dut):
        start_clock(dut)
        cycles, steps, model = await run_rom_program(dut, programs.DIRECTED[name], fwd_en=fwd_en, sw_extra=0)
        dut._log.info("%s fwd=%d: %d instructions in %d cycles" % (name, fwd_en, steps, cycles))
    body.__name__ = "test_directed_%s_fwd%d" % (name, fwd_en)
    body.__qualname__ = body.__name__
    return cocotb.test(skip=not ROMTEST)(body)


for _name in programs.DIRECTED:
    for _fwd in (1, 0):
        globals()["test_directed_%s_fwd%d" % (_name, _fwd)] = make_directed(_name, _fwd)


@cocotb.test(skip=not ROMTEST)
async def test_random_differential(dut):
    start_clock(dut)
    seed = int(os.environ.get("ARM16_SEED", "2026"))
    count = int(os.environ.get("ARM16_RANDOM_COUNT", "200"))
    for n in range(count):
        loop = (n % 10) == 9
        fwd = n % 2
        src = programs.random_program(seed + n, length=30, loop=loop)
        try:
            await run_rom_program(dut, src, fwd_en=fwd)
        except AssertionError as exc:
            dut._log.error("random program %d (seed %d, fwd %d) failed:\n%s" % (n, seed + n, fwd, src))
            raise
    dut._log.info("%d random programs matched the golden model" % count)


@cocotb.test(skip=not ROMTEST)
async def test_hazard_stall_counts(dut):
    """The dependent chain retires about 2x slower with forwarding off (spec 3.5)."""
    start_clock(dut)
    fast, _, _ = await run_rom_program(dut, programs.DIRECTED["dependent_chain"], fwd_en=1)
    slow, _, _ = await run_rom_program(dut, programs.DIRECTED["dependent_chain"], fwd_en=0)
    dut._log.info("dependent chain: %d cycles with forwarding, %d without" % (fast, slow))
    assert slow >= 2 * fast, "forwarding off should be at least 2x slower: %d vs %d" % (slow, fast)


@cocotb.test(skip=not ROMTEST)
async def test_demo_rom_program_counts(dut):
    """The shipped ROM program (D8) counts on VGA_VAL and reacts to FWD_EN."""
    start_clock(dut)
    src = open(os.path.join(os.path.dirname(__file__), "programs", "demo_rom.s")).read()
    words = asm.assemble(src)
    rates = {}
    for fwd in (1, 0):
        await reset_dut(dut, pins(fwd_en=fwd, boot_rom=1), rom_words=words, regs=[0] * 15)
        d = dp(dut)
        r0_start = int(d.register_file_unit.regs[0].value)
        await ClockCycles(dut.clk, 2000)
        rates[fwd] = int(d.register_file_unit.regs[0].value) - r0_start
        assert rates[fwd] > 0
    dut._log.info("loop iterations in 2000 cycles: fwd on %d, off %d" % (rates[1], rates[0]))
    assert rates[1] >= 2 * rates[0]


@cocotb.test(skip=not ROMTEST, expect_fail=True)
async def test_negative_known_failure(dut):
    """Deliberately wrong expectation so the suite is known to see (spec 14.4)."""
    start_clock(dut)
    _, _, model = await run_rom_program(dut, "MOV r0, #1\nADDS r1, r0, #1\nB .")
    assert int(dp(dut).register_file_unit.regs[1].value) == 3
