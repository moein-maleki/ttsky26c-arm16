"""Reset and lifecycle tests for the persistent QSPI Pmod models."""

import cocotb
from cocotb.triggers import ClockCycles, Edge, FallingEdge, First, ReadOnly, RisingEdge, SimTimeoutError, with_timeout
from cocotb.utils import get_sim_steps, get_sim_time

import qspi_models
import test as suite


class WrongTransferPhase(AssertionError):
    """The reset selector reached a different live transfer phase."""


def _deadline_after(duration_ns):
    return int(get_sim_time("step")) + get_sim_steps(duration_ns, "ns")


async def _before_deadline(trigger, deadline_step, label):
    remaining = deadline_step - int(get_sim_time("step"))
    if remaining <= 0:
        raise SimTimeoutError(f"overall deadline expired while waiting for {label}")
    try:
        return await with_timeout(trigger, remaining, "step")
    except SimTimeoutError as exc:
        raise SimTimeoutError(f"overall deadline expired while waiting for {label}") from exc


async def _condition_before_deadline(condition, trigger_factory, deadline_step, label):
    while not condition():
        await _before_deadline(trigger_factory(), deadline_step, label)


async def _clock_edges_before_deadline(dut, count, deadline_step, label):
    for _ in range(count):
        await _before_deadline(RisingEdge(dut.qspi_sck), deadline_step, label)


async def _assert_reset_idle(dut, deadline_step):
    dut.rst_n.value = 0
    await _before_deadline(ClockCycles(dut.clk, 2), deadline_step, "reset assertion")
    await _before_deadline(FallingEdge(dut.clk), deadline_step, "reset idle edge")
    assert int(dut.cs_flash_n.value) == 1
    assert int(dut.cs_ram_n.value) == 1
    assert int(dut.qspi_sck.value) == 0
    assert int(dut.sd_oe.value) == 0
    dut.rst_n.value = 1
    await _before_deadline(ClockCycles(dut.clk, 3), deadline_step, "reset release")


async def _reset_during_period(dut, run, chip_select, rising_edges, deadline_step, label):
    await _before_deadline(FallingEdge(chip_select), deadline_step, f"{label} select")
    await _clock_edges_before_deadline(dut, rising_edges, deadline_step, f"{label} phase")
    addresses_before = len(run.flash.first_addresses)
    await _assert_reset_idle(dut, deadline_step)
    await _condition_before_deadline(
        lambda: len(run.flash.first_addresses) > addresses_before,
        lambda: RisingEdge(dut.qspi_sck), deadline_step, f"{label} reboot address")
    assert run.flash.first_addresses[addresses_before] == 0


def _assert_current_psram_read(dut, run, command_count):
    assert int(dut.cs_ram_n.value) == 0, "PSRAM read ended before the reset phase"
    assert int(dut.cs_flash_n.value) == 1, "flash was selected during the PSRAM read"
    assert len(run.psram.commands) == command_count + 1
    command = run.psram.commands[command_count]
    if command != 0xEB:
        raise WrongTransferPhase("selected PSRAM command is %02X, expected EB" % command)


async def _select_psram_read_data(dut, run, deadline_step):
    saw_write = False
    while True:
        await _before_deadline(FallingEdge(dut.cs_ram_n), deadline_step, "PSRAM transaction select")
        command_count = len(run.psram.commands)
        address_count = len(run.psram.first_addresses)
        await _clock_edges_before_deadline(dut, 8, deadline_step, "PSRAM command decode")
        await ReadOnly()
        assert len(run.psram.commands) == command_count + 1, "selected PSRAM command was not decoded"
        command = run.psram.commands[command_count]
        dut._log.info("reset selector decoded current PSRAM command %02X" % command)
        if command != 0xEB:
            assert command == 0x38, "unexpected PSRAM command %02X" % command
            try:
                _assert_current_psram_read(dut, run, command_count)
            except WrongTransferPhase as exc:
                assert str(exc) == "selected PSRAM command is 38, expected EB"
            else:
                raise AssertionError("the PSRAM read selector accepted a write transaction")
            saw_write = True
            assert int(dut.cs_ram_n.value) == 0 and int(dut.cs_flash_n.value) == 1
            await _before_deadline(RisingEdge(dut.cs_ram_n), deadline_step, "rejected PSRAM write end")
            continue

        assert saw_write, "PSRAM read selector did not reject the preceding write"
        _assert_current_psram_read(dut, run, command_count)
        for edge in range(13):
            await _before_deadline(
                First(RisingEdge(dut.qspi_sck), RisingEdge(dut.cs_ram_n)),
                deadline_step, "PSRAM read-data phase")
            assert int(dut.cs_ram_n.value) == 0, "selected PSRAM read ended before data phase"
            assert int(dut.cs_flash_n.value) == 1, "flash was selected during the PSRAM read"
            if edge == 5:
                await ReadOnly()
                assert len(run.psram.first_addresses) == address_count + 1
                assert run.psram.first_addresses[address_count] == 0x10
        assert len(run.psram.commands) == command_count + 1
        assert run.psram.commands[command_count] == 0xEB
        assert int(dut.cs_ram_n.value) == 0 and int(dut.cs_flash_n.value) == 1
        dut._log.info("reset selector reached PSRAM EBh address 0x0010 read-data phase 21")
        return


@cocotb.test(timeout_time=5000, timeout_unit="us")
async def test_qe_zero_rejects_quad_read_then_same_model_recovers(dut):
    """Removing QE state must make a factory-state flash boot pass incorrectly."""
    suite.start_clock(dut)
    probe_bus = qspi_models.QspiBus(dut)
    probe_flash = qspi_models.FlashModel(dut, probe_bus, b"")
    assert hasattr(probe_flash, "program_qe"), "flash model has no explicit QE state"
    empty_deadline = _deadline_after(100)
    try:
        await _condition_before_deadline(
            lambda: False, lambda: RisingEdge(dut.clk), empty_deadline, "empty negative condition")
    except SimTimeoutError as exc:
        assert str(exc) == "overall deadline expired while waiting for empty negative condition"
    else:
        raise AssertionError("an empty condition did not reach its typed overall timeout")
    run = suite.FlashRun(dut, "MOV r0, #7\nADD r1, r0, #3")
    run.flash.program_qe(False)
    await suite.reset_dut(dut, run.ui)
    run.start_models()
    qe_deadline = _deadline_after(100000)
    await _condition_before_deadline(
        lambda: bool(run.flash.errors), lambda: Edge(dut.qspi_sck), qe_deadline, "QE rejection")
    assert run.flash.errors == ["EBh rejected because QE is 0"]
    assert run.flash.bytes_out == 0

    run.flash.program_qe(True)
    run.flash.errors.clear()
    await _assert_reset_idle(dut, _deadline_after(100000))
    await run.run_to_done()
    run.check()


@cocotb.test(timeout_time=5000, timeout_unit="us")
async def test_memory_state_survives_reset_at_each_transfer_phase(dut):
    """Removing live-model reset coverage must hide reset-time transfer faults."""
    suite.start_clock(dut)
    source = """
        MOV r0, #0x8000
        MOV r1, #0x1200
        ORR r1, r1, #0x34
        STR r1, [r0, #0x10]
        LDR r2, [r0, #0x10]
    """
    run = suite.FlashRun(dut, source)
    assert hasattr(run.flash, "program_qe"), "flash model has no explicit QE state"
    run.flash.program_qe(True)
    run.psram.mem[0x200:0x210] = bytes(range(0x80, 0x90))
    sentinel = bytes(run.psram.mem[0x200:0x210])
    await suite.reset_dut(dut, run.ui)
    run.start_models()
    deadline = _deadline_after(4000000)
    try:
        for rising_edges in (2, 10, 16, 21):
            await _reset_during_period(
                dut, run, dut.cs_flash_n, rising_edges, deadline, f"flash edge {rising_edges}")
            assert run.flash.qe is True
            assert bytes(run.psram.mem[0x200:0x210]) == sentinel
            assert int(dut.uio_in.value) == 0

        for rising_edges in (2, 10):
            await _reset_during_period(
                dut, run, dut.cs_ram_n, rising_edges, deadline, f"PSRAM edge {rising_edges}")
            assert run.flash.qe is True
            assert bytes(run.psram.mem[0x200:0x210]) == sentinel
            assert int(dut.uio_in.value) == 0

        run.psram.mem[0x10:0x12] = b"\xCC\xDD"
        await _reset_during_period(dut, run, dut.cs_ram_n, 15, deadline, "PSRAM partial byte")
        assert run.psram.mem[0x10:0x12] == b"\xCC\xDD"
        run.psram.mem[0x10:0x12] = b"\xCC\xDD"
        await _reset_during_period(dut, run, dut.cs_ram_n, 16, deadline, "PSRAM completed byte")
        assert run.psram.mem[0x10:0x12] == b"\x34\xDD"

        await _select_psram_read_data(dut, run, deadline)
        await _assert_reset_idle(dut, deadline)
        assert run.flash.qe is True
        assert bytes(run.psram.mem[0x200:0x210]) == sentinel

        await run.run_to_done()
        run.model.psram[0x200:0x210] = sentinel
        assert bytes(run.psram.mem) == bytes(run.model.psram)
        assert run.psram.word(0x8010) == 0x1234
        assert not run.flash.errors
        assert not run.psram.errors
        assert not run.monitor.errors
        assert not run.bus.errors
    finally:
        run.stop()
