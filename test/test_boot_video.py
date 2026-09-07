"""Shipped-ROM progress and forwarding proof through video pins, at RTL and powered gates."""
import os

import cocotb
from cocotb.triggers import ClockCycles, Timer

import test as support
import vga_capture

ROMTEST = os.environ.get('ROMTEST', 'no') == 'yes'
DEAD_ROM = os.environ.get('ARM16_DEAD_ROM', '0') == '1'


async def observe_shipped_rom(dut, fwd, verify_meter=True):
    """Read zero, the retirement meter, and the first nonzero ROM count through the same pins."""
    dut.video_monitor_enable.value = 1
    dut.video_monitor_quiet_bus.value = 1
    try:
        await support.reset_dut(dut, support.pins(fwd_en=fwd, boot_rom=1))
        initial = await vga_capture.capture_monitor_frame(dut, 0)
        assert initial == 0, 'ROM display did not start at zero'
        dut.ui_in.value = support.pins(fwd_en=fwd, boot_rom=1, disp_sel=1, user=1)
        meter = await vga_capture.capture_monitor_frame(dut, 1)
        # Frame 1 displays the partial first frame: 392,000 pixel clocks to VSYNC. Allow the
        # reset/pipeline phase at its boundaries, but distinguish the 13- and 29-cycle loops.
        low, high = (22614, 22617) if fwd else (10136, 10140)
        if verify_meter:
            assert low <= meter <= high, 'ROM meter fwd=%d: %d outside %d..%d' % (fwd, meter, low, high)
        dut.ui_in.value = support.pins(fwd_en=fwd, boot_rom=1)
        target_frame = 2 if fwd else 5
        count = await vga_capture.capture_monitor_frame(dut, target_frame)
        vga_capture.require_visible_count(count, 1)
        vga_capture.check_pin_monitor(dut)
        dut._log.info('SHIPPED ROM PIN PASS fwd=%d meter=%d count=%d frame=%d cycles=%d',
                      fwd, meter, count, target_frame, int(dut.video_sample_count.value))
        return meter
    finally:
        dut.video_monitor_enable.value = 0
        dut.video_monitor_quiet_bus.value = 0


@cocotb.test(skip=ROMTEST or DEAD_ROM)
async def test_shipped_rom_visible_progress(dut):
    """The real ROM must increment VGA_VAL and show the forwarding rate through the meter."""
    support.start_clock(dut)
    meters = {}
    for fwd in (1, 0):
        meters[fwd] = await observe_shipped_rom(dut, fwd)
    ratio = meters[1] / meters[0]
    assert 2.22 <= ratio <= 2.24, 'unexpected visible forwarding ratio %.6f' % ratio
    dut._log.info('SHIPPED ROM PIN RATIO %.6f', ratio)


@cocotb.test()
async def test_pin_monitor_rejects_early_sync(dut):
    """A separate synthetic pin source proves that early HSYNC and VSYNC are detected."""
    support.start_clock(dut)
    dut.video_monitor_enable.value = 0
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.ena.value = 1
    for mode, expected in ((0, 0), (1, 1), (2, 2)):
        dut.video_probe_enable.value = 0
        dut.video_probe_fault.value = mode
        await ClockCycles(dut.clk, 3)
        dut.video_probe_enable.value = 1
        await ClockCycles(dut.clk, 2000)
        await Timer(30, unit='ns')
        got = int(dut.video_probe_errors.value)
        assert got == expected, 'sync probe mode %d: error mask %d, expected %d' % (mode, got, expected)
    dut.video_probe_enable.value = 0


@cocotb.test(skip=not DEAD_ROM)
async def test_dead_rom_rejected_by_visible_progress(dut):
    """The separate B-dot ROM build must reach the visible-progress check and fail there."""
    support.start_clock(dut)
    try:
        await observe_shipped_rom(dut, 1, verify_meter=False)
    except vga_capture.VisibleProgressError as exc:
        dut._log.info('EXPECTED DEAD ROM REJECTION: %s', exc)
    else:
        raise AssertionError('a ROM that only branches to itself passed the visible progress check')
