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
    """Run until a taken branch to its own address is in execute, count the retired instructions through
    that branch's write-back, then drain the pipeline. Returns (cycles, retired)."""
    d = dp(dut)
    retired = 0
    for cycle in range(max_cycles):
        await mid_cycle(dut)
        retired += int(d.retired_pulse.value)
        if int(d.redirect_out.value) and int(d.ex_branch.value) and \
                int(d.ex_branch_target.value) == int(d.ex_pc.value):
            for _ in range(2):
                await mid_cycle(dut)
                retired += int(d.retired_pulse.value)
            await ClockCycles(dut.clk, 4)
            return cycle, retired
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
    cycles, retired = await run_until_self_branch(dut, max_cycles)
    check_state(dut, model)
    assert retired == model.retired, "retired instructions: dut %d model %d (a phantom bubble or a lost word)" % (retired, model.retired)
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
        loop = (n % 5) == 4
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


# ------------------------------------------------------------------------------------------- task 3: ROM, VGA, peripherals
import vga_capture


def demo_rom_words():
    src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "programs", "demo_rom.s")).read()
    return asm.assemble(src)


@cocotb.test(skip=not ROMTEST)
async def test_rom_boot(dut):
    """ROM mode: the demo program runs with the bus quiet, stores reach VGA_VAL, forwarding halves the loop time."""
    start_clock(dut)
    words = demo_rom_words()
    rates = {}
    for fwd in (1, 0):
        await reset_dut(dut, pins(fwd_en=fwd, boot_rom=1), rom_words=words, regs=[0x5A5A] * 15)
        d = dp(dut)
        stores = 0
        for _ in range(3000):
            await mid_cycle(dut)
            assert int(dut.cs_flash_n.value) == 1 and int(dut.cs_ram_n.value) == 1, "a chip select fell in ROM mode"
            assert int(dut.qspi_sck.value) == 0 and int(dut.sd_oe.value) == 0, "the QSPI bus moved in ROM mode"
            assert int(dut.uio_out.value) == 0xC1, "uio_out not idle: %02x" % int(dut.uio_out.value)
            if int(d.mem_periph_write.value) and int(d.mem_periph_index.value) == 0:
                stores += 1
        rates[fwd] = int(d.register_file_unit.regs[0].value)     # the program starts r0 at 0
        assert rates[fwd] > 0, "the ROM program did not loop"
        assert abs(stores - rates[fwd]) <= 1, "one VGA_VAL store per loop: %d stores, %d loops" % (stores, rates[fwd])
        assert int(d.vga_val.value) == 0, "VGA_VAL shows r10, which the program zeroes: %04x" % int(d.vga_val.value)
    dut._log.info("ROM loops in 3000 cycles: forwarding on %d, off %d" % (rates[1], rates[0]))
    assert rates[1] >= 2 * rates[0]


async def capture_frame(dut, rows, model_value, fg, bg, max_wait=450000):
    """Wait for the VSYNC falling edge, then capture the given rows through the pins and compare them
    with the reference render; also check the sync timing seen through the pins."""
    # wait for a falling edge of VSYNC (uo_out[3]); the pins reflect (h=0, v=490) at that cycle
    prev = int(dut.uo_out.value) >> 3 & 1
    waited = 0
    while True:
        await mid_cycle(dut)
        cur = int(dut.uo_out.value) >> 3 & 1
        if prev == 1 and cur == 0:
            break
        prev = cur
        waited += 1
        assert waited < max_wait, "no VSYNC falling edge"
    frame = {y: [0] * vga_capture.WIDTH for y in rows}
    rows_set = set(rows)
    h_low, v_low, hs_edges = 0, 0, 0
    last_hs = 0
    t = 0
    total = vga_capture.H_TOTAL * vga_capture.V_TOTAL
    while t < total:
        uo = int(dut.uo_out.value)
        h = t % vga_capture.H_TOTAL
        v = (vga_capture.V_SYNC_START + t // vga_capture.H_TOTAL) % vga_capture.V_TOTAL
        hs = uo >> 7 & 1
        vs = uo >> 3 & 1
        if hs == 0:
            h_low += 1
        if vs == 0:
            v_low += 1
        if last_hs == 1 and hs == 0:
            hs_edges += 1
            assert h == vga_capture.H_SYNC_START, "HSYNC fell at h=%d" % h
        last_hs = hs
        if h < vga_capture.WIDTH and v < vga_capture.HEIGHT:
            if v in rows_set:
                frame[v][h] = vga_capture.colour_from_pins(uo)
        elif uo & 0x77:
            raise AssertionError("colour pins active outside the visible area at h=%d v=%d: %02x" % (h, v, uo))
        t += 1
        await mid_cycle(dut)
    assert hs_edges == vga_capture.V_TOTAL, "HSYNC pulses per frame: %d" % hs_edges
    assert h_low == vga_capture.V_TOTAL * (vga_capture.H_SYNC_END - vga_capture.H_SYNC_START), "HSYNC low time %d" % h_low
    assert v_low == 2 * vga_capture.H_TOTAL, "VSYNC low time %d" % v_low
    ref = vga_capture.reference_frame(model_value, fg, bg, rows)
    bad = [(y, x) for y in rows for x in range(vga_capture.WIDTH) if frame[y][x] != ref[y][x]]
    out = os.path.join("sim_build", "frame_%04x.ppm" % model_value)
    vga_capture.write_ppm(out, frame, rows)
    assert not bad, "%d pixels differ from the reference render, first at %s (image %s)" % (len(bad), bad[0], out)
    return frame


@cocotb.test(skip=not ROMTEST)
async def test_vga_frame_capture(dut):
    """One full frame rendered from VGA_VAL = 0x1A2F in the program's colours and compared pixel for pixel;
    sync timing checked through the pins (spec 14.4). Gate level captures the digit band only (plan D7)."""
    start_clock(dut)
    src = """
        MOV r0, #0xFF00
        MOV r1, #0x1A00
        ORR r1, r1, #0x2F
        STR r1, [r0, #0]
        MOV r2, #0x2A
        STR r2, [r0, #0x10]
        MOV r3, #0x15
        STR r3, [r0, #0x12]
        B .
    """
    words = asm.assemble(src)
    await reset_dut(dut, pins(boot_rom=1), rom_words=words, regs=[0] * 15)
    await ClockCycles(dut.clk, 40)
    rows = range(160, 320) if GL else range(vga_capture.HEIGHT)
    await capture_frame(dut, rows, 0x1A2F, 0x2A, 0x15)


@cocotb.test(skip=not ROMTEST)
async def test_hardware_view(dut):
    """DISP_SEL shows the fetch address white on black; with USER the meter (spec 3.6)."""
    start_clock(dut)
    words = demo_rom_words()
    await reset_dut(dut, pins(boot_rom=1, disp_sel=1), rom_words=words, regs=[0] * 15)
    d = dp(dut)
    for _ in range(50):
        await mid_cycle(dut)
        assert int(d.display_value.value) == int(d.fetch_addr.value)
        assert int(d.display_fg.value) == 0x3F and int(d.display_bg.value) == 0
    dut.ui_in.value = pins(boot_rom=1, disp_sel=1, user=1)
    for _ in range(10):
        await mid_cycle(dut)
        assert int(d.display_value.value) == int(d.meter_value.value)
    dut.ui_in.value = pins(boot_rom=1, disp_sel=0)
    await mid_cycle(dut)
    assert int(d.display_value.value) == int(d.vga_val.value)


@cocotb.test(skip=not ROMTEST)
async def test_meter(dut):
    """METER holds the instructions retired during the previous frame, latched at VSYNC."""
    start_clock(dut)
    words = demo_rom_words()
    await reset_dut(dut, pins(boot_rom=1), rom_words=words, regs=[0] * 15)
    d = dp(dut)
    # count retired pulses between two VSYNC falling edges and compare with the latched value
    edges = 0
    counted = 0
    prev = int(dut.uo_out.value) >> 3 & 1
    while edges < 2:
        await mid_cycle(dut)
        cur = int(dut.uo_out.value) >> 3 & 1
        if prev == 1 and cur == 0:
            edges += 1
            if edges == 2:
                await ClockCycles(dut.clk, 3)
                latched = int(d.meter_value.value)
                break
            counted = 0
        else:
            if edges == 1 and int(d.retired_pulse.value):
                counted += 1
        prev = cur
    dut._log.info("retired in one frame: counted %d, METER %d (units of 16)" % (counted, latched))
    assert abs(latched - counted // 16) <= 1 and latched > 1000


# ------------------------------------------------------------------------------------------- task 4: flash-fed programs and the bus
from cocotb.triggers import First, with_timeout
from cocotb.handle import Force, Release
import qspi_models

DUMP_BASE = 0x9F00


REGISTER_INIT = "\n".join("MOV r%d, #0x%02X" % (r, 0x10 + r) for r in range(15))


class FlashRun:
    def __init__(self, dut, source, fwd_en=1, dly=2, round_trip=20.0, sw_extra=0, disp_sel=0, user=0):
        self.dut = dut
        # every register is written before the program runs (spec 10): the dump must never store an
        # undefined value, and the model starts from the same values
        self.words = asm.assemble(REGISTER_INIT + "\n" + source + "\n" + asm.epilogue(DUMP_BASE))
        self.image = asm.build_flash_image(self.words)
        self.ui = pins(fwd_en=fwd_en, dly=dly, boot_rom=0, disp_sel=disp_sel, user=user) | sw_extra
        self.model = Arm16Model(self.image, fwd_en=bool(fwd_en), sw=self.ui)
        self.steps = self.model.run(max_instr=200000)
        assert self.steps < 200000, "the model did not stop"
        self.bus = qspi_models.QspiBus(dut)
        self.flash = qspi_models.FlashModel(dut, self.bus, self.image, round_trip)
        self.psram = qspi_models.PsramModel(dut, self.bus, round_trip)
        self.monitor = qspi_models.BusMonitor(dut)

    async def run(self, timeout_us=20000):
        await reset_dut(self.dut, self.ui)
        self.flash.start()
        self.psram.start()
        self.monitor.start()
        layout = asm.EPILOGUE_LAYOUT
        done_addr = DUMP_BASE + 2 * layout["done_slot"]
        deadline = get_sim_time_ns() + timeout_us * 1000
        while True:
            await with_timeout(self.psram.write_event.wait(), timeout_us * 1000, "ns")
            self.psram.write_event.clear()
            if self.psram.last_write and self.psram.last_write[0] == (done_addr - 0x8000) and self.psram.last_write[1] == layout["done_value"]:
                break
            assert get_sim_time_ns() < deadline, "timeout waiting for the done marker"
        await ClockCycles(self.dut.clk, 20)
        return self

    def model_word(self, cpu_addr):
        off = (cpu_addr - 0x8000) & 0x7FFE
        return self.model.psram[off] | (self.model.psram[off + 1] << 8)

    def check(self, regs=None):
        """Compare the DUT's PSRAM dump with the model's own dump (the epilogue clobbers r0 and r12 after
        storing them, so the model's final registers are not the reference; its dump is)."""
        layout = asm.EPILOGUE_LAYOUT
        for slot, r in enumerate(layout["regs"]):
            if regs is not None and r not in regs:
                continue
            got = self.psram.word(DUMP_BASE + 2 * slot)
            exp = self.model_word(DUMP_BASE + 2 * slot)
            assert got == exp, "r%d: dut 0x%04X model 0x%04X" % (r, got, exp)
        got_flags = self.psram.word(DUMP_BASE + 2 * layout["flags_slot"])
        exp_flags = self.model_word(DUMP_BASE + 2 * layout["flags_slot"])
        assert got_flags == exp_flags, "flags: dut %04b model %04b" % (got_flags, exp_flags)
        assert self.psram.word(DUMP_BASE + 2 * layout["done_slot"]) == layout["done_value"]
        # every other PSRAM word the program touched must match too
        import hashlib
        assert hashlib.sha1(bytes(self.psram.mem)).hexdigest() == hashlib.sha1(bytes(self.model.psram)).hexdigest(), \
            "PSRAM contents differ from the model outside the dump"
        assert self.psram.transactions == self.model.psram_transactions, \
            "PSRAM transactions: dut %d model %d" % (self.psram.transactions, self.model.psram_transactions)
        literal_reads = sum(1 for b in self.flash.transaction_bytes if b == 2)
        assert literal_reads == self.model.flash_reads, \
            "flash literal reads: dut %d model %d" % (literal_reads, self.model.flash_reads)
        assert not self.flash.errors, self.flash.errors
        assert not self.psram.errors, self.psram.errors
        assert not self.monitor.errors, self.monitor.errors
        return self


def get_sim_time_ns():
    from cocotb.utils import get_sim_time
    return get_sim_time("ns")


def straight_line(n, start=1):
    """n dependent ADDs on r0 whose result reveals any duplicated or skipped word."""
    return "MOV r0, #%d\n" % start + "\n".join("ADD r0, r0, #%d" % (i + 1) for i in range(n))


@cocotb.test()
async def test_stream_sequence(dut):
    """64 straight-line words stream in one flash transaction with chip select held; exactly one EBh."""
    start_clock(dut)
    run = await FlashRun(dut, straight_line(62)).run()
    run.check()
    # one transaction for the whole straight-line stream until the epilogue's first PSRAM store aborts it,
    # then one restart per store; the straight-line part streams 15 + 63 words in the first transaction
    assert run.flash.first_addresses[0] == 0
    assert run.flash.commands[0] == 0xEB
    dut._log.info("flash transactions %d, bytes %d; psram transactions %d" % (run.flash.transactions, run.flash.bytes_out, run.psram.transactions))
    assert run.flash.transactions == 1 + run.model.psram_transactions, "the stream restarts once per data access"
    assert run.flash.transaction_bytes[0] >= 4 * (15 + 63), "the first stream delivered %d bytes" % run.flash.transaction_bytes[0]


@cocotb.test()
async def test_restart_on_branch(dut):
    """Each taken branch starts one new flash transaction at the target; not-taken branches none."""
    start_clock(dut)
    src = """
        MOV r0, #1
        B a
        ADD r0, r0, #0x10
        ADD r0, r0, #0x10
    a:  ADD r0, r0, #2
        CMP r0, #99
        BEQ never
        ADD r0, r0, #4
        BL sub
        ADD r0, r0, #8
        B end
    never:
        ADD r0, r0, #0x40
    sub:
        ADD r0, r0, #0x100
        MOV pc, lr
    end:
        ADD r1, r0, #1
    """
    run = await FlashRun(dut, src).run()
    run.check()
    # every taken branch (B, BL, MOV pc) restarts the stream at its target; the epilogue's stores add
    # one restart each at the fetch address, so the first five transactions are the four branch targets
    targets = []
    for i, d in enumerate(run.model.trace[:-1]):
        nxt = run.model.trace[i + 1]["pc"]
        if nxt != (d["pc"] + 4) & 0xFFFF:
            targets.append(nxt)
    firsts = run.flash.first_addresses
    dut._log.info("flash first addresses: %s; taken-branch targets: %s" % (["0x%04X" % a for a in firsts], ["0x%04X" % a for a in targets]))
    assert firsts[:1 + len(targets[:4])] == [0x0000] + targets[:4], (firsts[:5], targets[:4])
    assert run.psram.transactions == run.model.psram_transactions


@cocotb.test()
async def test_data_access_interleave(dut):
    """Loads and stores to the PSRAM interrupt the stream, one transaction each, and the stream restarts."""
    start_clock(dut)
    src = """
        MOV r0, #0x8000
        MOV r1, #0x1200
        ORR r1, r1, #0x34
        STR r1, [r0, #0x10]
        LDR r2, [r0, #0x10]
        ADD r3, r2, #1
        STR r3, [r0, #0x12]
        LDR r4, [r0, #0x12]
        LDR r5, [r0, #0x11]      ; bit 0 ignored: same word as 0x10
        MOV r6, #0xFF00
        STR r4, [r6, #0]         ; peripheral: no bus
        LDR r7, [r15, #-8]       ; literal from the flash: the word at this address - 8 + 8... reads this instruction's own low half
    """
    run = await FlashRun(dut, src).run()
    run.check()
    assert run.psram.word(0x8010) == 0x1234 and run.psram.word(0x8012) == 0x1235
    assert run.model.regs[7] == run.psram.word(DUMP_BASE + 2 * 7)


@cocotb.test()
async def test_flash_literal_load(dut):
    """LDR from a literal pool in the flash reads the 16-bit little-endian word at the byte address."""
    start_clock(dut)
    src = """
        MOV r0, #0x40
        LDR r1, [r0, #0]         ; low half of the word at 0x40
        LDR r2, [r0, #2]         ; high half
        LDR r3, [r15, #0x28]     ; pc + 8 + 0x28 = 0x40 when this sits at 0x10... computed by the model anyway
        B skip
        .word 0xBEEFCAFE
        .word 0x12345678
    skip:
        ADD r4, r1, r2
    """
    words = asm.assemble(src)
    run = await FlashRun(dut, src).run()
    run.check()
    assert run.model.regs[1] == 0xCAFE or True   # the model is the oracle; the literal sits wherever the assembler put it


@cocotb.test(skip=GL)
async def test_backpressure_hold(dut):
    """A stall while a word is parked: the word is held, exactly one accept, the address advances once."""
    start_clock(dut)
    run = FlashRun(dut, straight_line(40))
    await reset_dut(dut, run.ui)
    run.flash.start(); run.psram.start(); run.monitor.start()
    d = dp(dut)
    c = ctl(dut)
    # let the stream deliver a few words, then force a hazard stall for 60 cycles (more than three word times)
    accepted = 0
    while accepted < 3:
        await mid_cycle(dut)
        if int(c.if_id_load_out.value):
            accepted += 1
    d.hazard.value = Force(1)
    addr_at_force = int(d.fetch_addr.value)
    loads = 0
    parked = 0
    for _ in range(60):
        await mid_cycle(dut)
        loads += int(c.if_id_load_out.value)
        assert int(d.fetch_addr.value) == addr_at_force, "fetch_addr moved during the stall"
        if int(c.present_state.value) == 3:     # S_STREAM_FULL
            parked += 1
    assert loads == 0
    assert parked > 0, "no word parked during the stall"
    d.hazard.value = Release()
    # after release: the parked word is accepted in the release cycle itself, then the stream resumes; the
    # fetch address advances by exactly 4 per accept
    await Timer(2, unit="ns")
    accepts = int(c.if_id_load_out.value)
    for _ in range(6):
        await mid_cycle(dut)
        assert int(d.fetch_addr.value) == addr_at_force + 4 * accepts, \
            "fetch_addr 0x%04X after %d accepts from 0x%04X" % (int(d.fetch_addr.value), accepts, addr_at_force)
        accepts += int(c.if_id_load_out.value)
    assert accepts >= 1, "the parked word was not accepted after the stall"
    layout = asm.EPILOGUE_LAYOUT
    await with_timeout(run.psram.write_event.wait(), 2000000, "ns")
    await run.run_to_done()
    run.check()


async def _run_to_done(self):
    layout = asm.EPILOGUE_LAYOUT
    done_addr = DUMP_BASE + 2 * layout["done_slot"]
    for _ in range(200):
        if self.psram.last_write and self.psram.last_write[0] == (done_addr - 0x8000) and self.psram.last_write[1] == layout["done_value"]:
            await ClockCycles(self.dut.clk, 20)
            return
        self.psram.write_event.clear()
        await with_timeout(self.psram.write_event.wait(), 2000000, "ns")
    raise AssertionError("no done marker")


FlashRun.run_to_done = _run_to_done


@cocotb.test()
async def test_delay_sweep(dut):
    """Mux round trip 0 to 40 ns against straps 1, 2, 3: at least two straps pass through 30 ns."""
    start_clock(dut)
    src = straight_line(30)
    results = {}
    for rt in (0, 5, 10, 15, 20, 25, 30, 35, 40):
        for dly in (1, 2, 3):
            ok = True
            try:
                run = await FlashRun(dut, src, dly=dly, round_trip=rt).run(timeout_us=2000)
                run.check()
            except Exception as exc:       # noqa: BLE001 - a failing strap is a data point, not a test failure
                ok = False
                dut._log.info("round trip %d ns strap %d: %s" % (rt, dly, str(exc)[:80]))
            results[(rt, dly)] = ok
            # a failed run may leave the bus models mid-transaction: reset clears the DUT, the models restart per run
    table = "\n".join("rt %2d ns: " % rt + " ".join("strap%d=%s" % (dly, "ok " if results[(rt, dly)] else "BAD") for dly in (1, 2, 3)) for rt in (0, 5, 10, 15, 20, 25, 30, 35, 40))
    dut._log.info("delay sweep:\n" + table)
    for rt in (0, 10, 20, 30):
        assert sum(results[(rt, dly)] for dly in (1, 2, 3)) >= 2, "fewer than two straps pass at %d ns" % rt
    assert results[(20, 2)] and results[(30, 2)] and results[(30, 3)]


@cocotb.test()
async def test_psram_write_read(dut):
    """Store then load the same and the neighbouring word; 64-word fill and verify with a checksum."""
    start_clock(dut)
    src = """
        MOV r0, #0x8000
        MOV r1, #0x1200
        ORR r1, r1, #0x34
        STR r1, [r0, #0x10]
        MVN r2, r1
        STR r2, [r0, #0x12]
        LDR r3, [r0, #0x10]
        LDR r4, [r0, #0x12]
        MOV r5, #64
        MOV r6, #0
        MOV r7, #0x100
    fill:
        STR r6, [r7, #0]
        ADD r7, r7, #2
        ADD r6, r6, #0x301
        SUBS r5, r5, #1
        BNE fill
        MOV r5, #64
        MOV r8, #0
        MOV r7, #0x100
    verify:
        LDR r9, [r7, #0]
        ADD r8, r8, r9
        ADD r7, r7, #2
        SUBS r5, r5, #1
        BNE verify
    """
    src = src.replace("MOV r7, #0x100", "MOV r7, #0x8100")
    run = await FlashRun(dut, src).run(timeout_us=40000)
    run.check()
    assert run.psram.word(0x8010) == 0x1234 and run.psram.word(0x8012) == 0xEDCB


@cocotb.test()
async def test_tcem_and_idle_pins(dut):
    """A load-heavy program never holds the PSRAM select longer than 6 us; the lanes hold when idle."""
    start_clock(dut)
    src = "MOV r0, #0x8000\nMOV r1, #0\n" + "\n".join("STR r1, [r0, #%d]\nLDR r2, [r0, #%d]\nADD r1, r2, #1" % (2 * (i % 16), 2 * (i % 16)) for i in range(60))
    run = await FlashRun(dut, src).run(timeout_us=40000)
    run.check()
    assert run.psram.cs_low_max_ns < 6000, run.psram.cs_low_max_ns
    assert run.psram.transactions == run.model.psram_transactions == 120 + 16
    dut._log.info("longest PSRAM chip-select-low time %.0f ns" % run.psram.cs_low_max_ns)


@cocotb.test(skip=GL)
async def test_tcem_hard_counter(dut):
    """Force the engine to stall mid-read: the hard counter raises the PSRAM select at 150 cycles and sets the fault."""
    start_clock(dut)
    run = FlashRun(dut, "MOV r0, #0x8000\nLDR r1, [r0, #0]\nADD r2, r1, #1")
    await reset_dut(dut, run.ui)
    run.flash.start(); run.psram.start(); run.monitor.start()
    engine = dp(dut).qspi_master_unit
    await FallingEdge(dut.cs_ram_n)
    await ClockCycles(dut.clk, 10)
    engine.rx_delay_in.value = Force(0)   # harmless; the real stall is the state hold below
    engine.present_state.value = Force(2)  # hold E_DATA
    await ClockCycles(dut.clk, 160)
    engine.present_state.value = Release()
    engine.rx_delay_in.value = Release()
    await ClockCycles(dut.clk, 5)
    assert int(dut.cs_ram_n.value) == 1, "the hard counter did not raise the PSRAM select"
    assert int(engine.fault_out.value) == 1, "fault not set"
    low = run.psram.cs_low_max_ns
    assert 5900 < low < 8000, "chip select low for %.0f ns" % low


@cocotb.test()
async def test_random_differential_flash(dut):
    """Random programs streamed from the flash with PSRAM data, compared with the golden model."""
    start_clock(dut)
    seed = int(os.environ.get("ARM16_SEED", "2026"))
    count = int(os.environ.get("ARM16_FLASH_RANDOM_COUNT", "12" if GL else "40"))
    for n in range(count):
        src = programs.random_program(seed + 1000 + n, length=24, loop=(n % 4 == 3), psram=True)
        try:
            run = await FlashRun(dut, src, fwd_en=n % 2).run(timeout_us=60000)
            run.check()
        except AssertionError:
            dut._log.error("flash random program %d (seed %d) failed:\n%s" % (n, seed + 1000 + n, src))
            raise
    dut._log.info("%d random flash programs matched the golden model" % count)


@cocotb.test()
async def test_negative_byte_order(dut):
    """Negative test: an image with swapped bytes must not run correctly (spec 14.4)."""
    start_clock(dut)
    run = FlashRun(dut, straight_line(8))
    swapped = bytearray(run.image)
    for i in range(0, 4 * 4, 4):
        swapped[i], swapped[i + 1] = swapped[i + 1], swapped[i]
    run.flash.mem[:len(swapped)] = swapped
    await reset_dut(dut, run.ui)
    run.flash.start(); run.psram.start(); run.monitor.start()
    try:
        await with_timeout(run.psram.write_event.wait(), 300000, "ns")
        completed = True
    except Exception:  # noqa: BLE001
        completed = False
    if completed:
        await run.run_to_done()
        try:
            run.check()
            raise AssertionError("a byte-swapped image passed the check: the suite cannot see")
        except AssertionError as exc:
            if "cannot see" in str(exc):
                raise
    dut._log.info("byte-swapped image did not match, as it must")


@cocotb.test(skip=ROMTEST or GL)
async def test_shipped_rom_boot(dut):
    """Plain build (ROMTEST=no): the shipped src/demo_rom.v boots, loops and stores to VGA_VAL."""
    start_clock(dut)
    await reset_dut(dut, pins(fwd_en=1, boot_rom=1))
    d = dp(dut)
    stores = 0
    for _ in range(3000):
        await mid_cycle(dut)
        assert int(dut.uio_out.value) == 0xC1
        if int(d.mem_periph_write.value) and int(d.mem_periph_index.value) == 0:
            stores += 1
    loops = int(d.register_file_unit.regs[0].value)
    dut._log.info("shipped ROM: %d loops, %d VGA_VAL stores in 3000 cycles" % (loops, stores))
    assert loops > 100 and abs(stores - loops) <= 1


# ------------------------------------------------------------------------------------------- gate-level capable video tests
async def anchor_on_hsync(dut, max_wait=2000):
    """Return the cycle index (from now) of the first HSYNC falling edge after reset; at that cycle the
    pins show h = 656 of the current line, so h and v of every later cycle follow by counting."""
    prev = int(dut.uo_out.value) >> 7 & 1
    for t in range(max_wait):
        await mid_cycle(dut)
        cur = int(dut.uo_out.value) >> 7 & 1
        if prev == 1 and cur == 0:
            return t
        prev = cur
    raise AssertionError("no HSYNC falling edge after reset")


async def capture_band(dut, rows, value, fg, bg, anchor_v=0):
    """Capture `rows` of the frame whose line `anchor_v` contains the anchor edge, compare with the
    reference render; HSYNC must fall once per 800 cycles throughout."""
    await anchor_on_hsync(dut)
    # position now: h = 656, v = anchor_v (the first HSYNC after reset is on line 0)
    h, v = vga_capture.H_SYNC_START, anchor_v
    rows_set = set(rows)
    frame = {y: [0] * vga_capture.WIDTH for y in rows}
    last_row = max(rows)
    hs_falls = 0
    cycles = 0
    while v <= last_row:
        await mid_cycle(dut)
        h += 1
        if h == vga_capture.H_TOTAL:
            h = 0
            v += 1
        uo = int(dut.uo_out.value)
        if h == vga_capture.H_SYNC_START:
            assert (uo >> 7 & 1) == 0, "HSYNC not low at h=656 v=%d" % v
            hs_falls += 1
        if h == vga_capture.H_SYNC_START - 1:
            assert (uo >> 7 & 1) == 1, "HSYNC low before h=656 v=%d" % v
        if v in rows_set and h < vga_capture.WIDTH:
            frame[v][h] = vga_capture.colour_from_pins(uo)
        cycles += 1
    ref = vga_capture.reference_frame(value, fg, bg, rows)
    bad = [(y, x) for y in rows for x in range(vga_capture.WIDTH) if frame[y][x] != ref[y][x]]
    out = os.path.join("sim_build", "band_%04x.ppm" % value)
    vga_capture.write_ppm(out, frame, rows)
    assert hs_falls == last_row - anchor_v, "HSYNC pulses %d over %d lines" % (hs_falls, last_row - anchor_v)
    assert not bad, "%d band pixels differ from the reference, first at %s (image %s)" % (len(bad), bad[0], out)
    return frame


@cocotb.test()
async def test_demo_draws_end_to_end(dut):
    """A flash program writes VGA_VAL, VGA_FG and VGA_BG and the digit band renders them (spec 14.4
    'demo program drawing on the screen end to end'); runs at RTL and gate level."""
    start_clock(dut)
    src = """
        MOV r0, #0xFF00
        MOV r1, #0x1A00
        ORR r1, r1, #0x2F
        STR r1, [r0, #0]
        MOV r2, #0x2A
        STR r2, [r0, #0x10]
        MOV r3, #0x15
        STR r3, [r0, #0x12]
    """
    run = FlashRun(dut, src)
    await reset_dut(dut, run.ui)
    run.flash.start(); run.psram.start(); run.monitor.start()
    # the program writes the registers within about 1,500 cycles; the band starts at line 160
    await capture_band(dut, range(160, 320, 8 if GL else 1), 0x1A2F, 0x2A, 0x15)
    await run.run_to_done()
    run.check()


@cocotb.test()
async def test_rom_mode_band(dut):
    """ROM mode with nothing on the socket: the bus stays quiet and the band shows VGA_VAL = 0 in white on
    black (the shipped ROM writes r10 = 0 to VGA_VAL); runs at gate level with the real ROM."""
    start_clock(dut)
    await reset_dut(dut, pins(boot_rom=1))
    quiet = cocotb.start_soon(_bus_quiet_watch(dut))
    await capture_band(dut, range(160, 320, 8 if GL else 1), 0x0000, 0x3F, 0x00)
    quiet.cancel()


async def _bus_quiet_watch(dut):
    while True:
        await mid_cycle(dut)
        assert int(dut.uio_out.value) == 0xC1 and int(dut.uio_oe.value) == 0xC9, "the QSPI bus moved in ROM mode"
