"""Behavioural models of the QSPI Pmod chips for cocotb (spec 14.3), written from the datasheet facts in
scratch_pad/2026-09-04_sep/03_memory_options/evidence/agent_qspi_part_timing.md.

W25Q128JV flash: SPI-mode EBh Fast Read Quad I/O: command on one lane (8 SCK), 24-bit address on four
lanes (6 SCK), mode byte (2 SCK, M5-4 = 10 would arm continuous read: forbidden here), 4 dummy SCK, then
data on four lanes, high nibble first, auto-increment until the chip select rises. tCLQV 6 ns after the
falling edge, tCLQX 1.5 ns hold, tSHSL 10 ns.
APS6404L PSRAM: EBh Fast Read Quad: command 8, address 6, 6 wait SCK, then data; 38h Quad Write: command
8, address 6, data from period 14; tCEM 8 us maximum chip-select-low time; tCPH 18 ns minimum high time.
Both models add a configurable round-trip delay (the TinyTapeout mux) to the return path and drive X
between the old and the new nibble, so the sampling strap sweep is honest."""

import cocotb
from cocotb.triggers import Edge, FallingEdge, First, RisingEdge, Timer, ReadOnly, Event
from cocotb.types import LogicArray
from cocotb.utils import get_sim_time

T_CLQV_NS = 6.0
T_CLQX_NS = 1.5
T_SHSL_NS = 10.0
T_CPH_NS = 18.0
T_CEM_NS = 8000.0


def resolved(signal):
    """The signal as an int, or None when it is not resolvable. The gate-level netlist can carry an X
    from the lanes' X window into a control pin in a strap setting the delay sweep expects to fail; the
    models record that as a protocol error instead of raising inside a coroutine, which would cancel
    the test in the ReadOnly phase."""
    try:
        return int(signal.value)
    except ValueError:
        return None


class QspiBus:
    """Composes uio_in from the chip that drives the lanes (only one chip is ever selected)."""

    def __init__(self, dut):
        self.dut = dut
        self.errors = []
        self._owner = None
        self._generation = None
        self._release_owner = None
        self._release_generation = None
        self.release()

    def begin(self, owner, generation):
        if self._owner is not None and (self._owner is not owner or self._generation != generation):
            self.errors.append("two QSPI chips attempted to own the input lanes")
            self.dut.uio_in.value = LogicArray("00XX0XX0")
            return False
        self._owner = owner
        self._generation = generation
        self._release_owner = None
        self._release_generation = None
        return True

    def end(self, owner, generation):
        if self._owner is not owner or self._generation != generation:
            return False
        self._owner = None
        self._generation = None
        self._release_owner = owner
        self._release_generation = generation
        return True

    def drive(self, nibble, owner=None, generation=None):
        if owner is not None and (self._owner is not owner or self._generation != generation):
            return False
        v = 0
        v |= (nibble & 1) << 1
        v |= ((nibble >> 1) & 1) << 2
        v |= ((nibble >> 2) & 1) << 4
        v |= ((nibble >> 3) & 1) << 5
        self.dut.uio_in.value = v
        return True

    def drive_x(self, owner=None, generation=None):
        if owner is not None and (self._owner is not owner or self._generation != generation):
            return False
        self.dut.uio_in.value = LogicArray("00XX0XX0")
        return True

    def release(self, owner=None, generation=None):
        if owner is not None:
            if self._owner is not None:
                return False
            if self._release_owner is not owner or self._release_generation != generation:
                return False
        self._owner = None
        self._generation = None
        self._release_owner = None
        self._release_generation = None
        self.dut.uio_in.value = 0
        return True

    def cancel(self, owner):
        if self._owner is owner or self._release_owner is owner:
            self.release()


class ChipModel:
    """Common transaction decoding for both chips. Subclasses define the protocol constants."""

    name = "chip"
    read_wait_periods = 4        # periods after the address (and mode) before data
    has_mode_byte = True

    def __init__(self, dut, bus, cs_signal, round_trip_ns=20.0, size=32768):
        self.dut = dut
        self.bus = bus
        self.cs = cs_signal
        self.round_trip = float(round_trip_ns)
        self.mem = bytearray(size)
        self.size = size
        self.errors = []
        self.transactions = 0
        self.bytes_out = 0
        self.bytes_in = 0
        self.first_addresses = []
        self.commands = []
        self.transaction_bytes = []
        self.cs_low_max_ns = 0.0
        self.last_cs_rise_ns = None
        self.sd_last_change_ns = None
        self.selected = False
        self.generation = 0
        self._tasks = []
        self.write_event = Event()
        self.last_write = None

    def error(self, text):
        self.errors.append(text)
        self.dut._log.error("%s model: %s" % (self.name, text))

    def start(self):
        self._tasks = [cocotb.start_soon(self.run()), cocotb.start_soon(self._monitor_sd())]

    def stop(self):
        for t in self._tasks:
            t.cancel()
        self._tasks = []
        self.selected = False
        self.generation += 1
        self.bus.cancel(self)

    async def _monitor_sd(self):
        while True:
            await Edge(self.dut.sd_out)
            self.sd_last_change_ns = get_sim_time("ns")

    def data_start_period(self):
        return 8 + 6 + (2 if self.has_mode_byte else 0) + self.read_wait_periods

    async def run(self):
        while True:
            await FallingEdge(self.cs)
            t_low = get_sim_time("ns")
            self.generation += 1
            generation = self.generation
            self.selected = True
            if not self.bus.begin(self, generation):
                self.error("could not own the QSPI input lanes")
            if self.last_cs_rise_ns is not None and t_low - self.last_cs_rise_ns < self.min_cs_high_ns():
                self.error("chip select re-selected after %.1f ns, minimum %.1f" % (t_low - self.last_cs_rise_ns, self.min_cs_high_ns()))
            sck = resolved(self.dut.qspi_sck)
            if sck is None:
                self._abandon(0, "SCK at the chip select fall", generation)
                continue
            if sck != 0:
                self.error("chip select fell while SCK was high")
            self.transactions += 1
            await self.transaction(t_low, generation)

    def min_cs_high_ns(self):
        return T_SHSL_NS

    def command_allowed(self, command):
        return True

    async def transaction(self, t_low, generation):
        period = 0
        command = 0
        address = 0
        mode = 0
        write_nibbles = []
        data_start = self.data_start_period()
        reading = None
        command_blocked = False
        while True:
            trig = await First(RisingEdge(self.dut.qspi_sck), FallingEdge(self.dut.qspi_sck), RisingEdge(self.cs))
            now = get_sim_time("ns")
            cs = resolved(self.cs)
            sck = resolved(self.dut.qspi_sck)
            if cs is None or sck is None:
                self._abandon(period, "chip select or SCK", generation)
                return
            if trig is RisingEdge(self.cs) or cs == 1:
                break
            if sck == 1:
                # the chip samples the lanes on the rising edge: setup and hold checks, then decode
                sd = resolved(self.dut.sd_out)
                oe = resolved(self.dut.sd_oe)
                if sd is None or oe is None:
                    self._abandon(period, "the lanes or the lane enable", generation)
                    return
                if self.sd_last_change_ns is not None and now - self.sd_last_change_ns < 5.0 and oe:
                    self.error("data changed %.1f ns before the SCK rising edge of period %d" % (now - self.sd_last_change_ns, period))
                if period < 8:
                    if oe != 0b0001:
                        self.error("command period %d drives lanes %s, expected 0001" % (period, format(oe, "04b")))
                    command = ((command << 1) | (sd & 1)) & 0xFF
                    if period == 7:
                        self.commands.append(command)
                        command_blocked = not self.command_allowed(command)
                        reading = None if command_blocked else self.is_read(command)
                        if reading is None and not command_blocked:
                            self.error("unknown command %02X" % command)
                            reading = True
                elif period < 14:
                    if oe != 0b1111:
                        self.error("address period %d drives lanes %s" % (period, format(oe, "04b")))
                    address = ((address << 4) | sd) & 0xFFFFFF
                    if period == 13:
                        self.first_addresses.append(address)
                        if address >= self.size:
                            self.error("address %06X outside the %d-byte array" % (address, self.size))
                elif self.has_mode_byte and period < 16:
                    if oe != 0b1111:
                        self.error("mode period %d drives lanes %s" % (period, format(oe, "04b")))
                    mode = ((mode << 4) | sd) & 0xFF
                    if period == 15 and (mode & 0x30) == 0x20:
                        self.error("mode byte %02X arms continuous read" % mode)
                elif command_blocked:
                    pass
                elif not reading and period >= 14:
                    # linear burst: every clocked-in byte lands in memory (the real part keeps writing)
                    if oe != 0b1111:
                        self.error("write data period %d drives lanes %s" % (period, format(oe, "04b")))
                    write_nibbles.append(sd)
                    if len(write_nibbles) % 2 == 0:
                        byte = (write_nibbles[-2] << 4) | write_nibbles[-1]
                        idx = (address + len(write_nibbles) // 2 - 1) % self.size
                        self.mem[idx] = byte
                        self.bytes_in += 1
                        self.last_write = (idx, byte)
                        self.write_event.set()
                else:
                    if reading and oe != 0:
                        self.error("master drives lanes %s during period %d of a read" % (format(oe, "04b"), period))
                if oe:
                    # hold: no edge on the data lanes or their enables for 5 ns after the SCK rising edge
                    trig = await First(Edge(self.dut.sd_out), Edge(self.dut.sd_oe), Timer(5, unit="ns"))
                    if not isinstance(trig, Timer):
                        self.error("data or enable changed within 5 ns after the SCK rising edge of period %d" % period)
            else:
                # falling edge of `period`: a read launches nibble (period - data_start + 1)
                if reading and period >= data_start - 1:
                    nib_index = period - (data_start - 1)
                    self._tasks.append(cocotb.start_soon(self._drive_nibble(address, nib_index, generation)))
                period += 1
        t_high = get_sim_time("ns")
        self.transaction_bytes.append(self.bytes_out - sum(self.transaction_bytes))
        self.last_cs_rise_ns = t_high
        self.cs_low_max_ns = max(self.cs_low_max_ns, t_high - t_low)
        if t_high - t_low > self.max_cs_low_ns():
            self.error("chip select low for %.0f ns, maximum %.0f" % (t_high - t_low, self.max_cs_low_ns()))
        sck = resolved(self.dut.qspi_sck)
        if sck is None:
            self.error("SCK unresolvable when the chip select rose")
        elif sck != 0 and resolved(self.dut.rst_n) != 0:
            self.error("chip select rose while SCK was high")
        self.selected = False
        self.bus.end(self, generation)
        self._tasks.append(cocotb.start_soon(self._release_after(self.round_trip / 2 + 7.0, generation)))

    def max_cs_low_ns(self):
        return 1e12

    def _abandon(self, period, what, generation):
        """Stop decoding: a control pin is X or Z. The error fails check(); the lanes go idle."""
        self.error("%s unresolvable in period %d at %.0f ns" % (what, period, get_sim_time("ns")))
        self.selected = False
        self.bus.end(self, generation)
        self.bus.release(self, generation)

    async def _drive_nibble(self, address, nib_index, generation):
        """Drive X then the nibble on the lanes, delayed by the round trip; only while selected."""
        await Timer(self.round_trip + T_CLQX_NS, unit="ns")
        if not self.selected or generation != self.generation:
            return
        if not self.bus.drive_x(self, generation):
            return
        await Timer(T_CLQV_NS - T_CLQX_NS, unit="ns")
        if not self.selected or generation != self.generation:
            return
        byte = self.mem[(address + nib_index // 2) % self.size]
        nibble = (byte >> 4) & 0xF if nib_index % 2 == 0 else byte & 0xF
        if not self.bus.drive(nibble, self, generation):
            return
        if nib_index % 2 == 1:
            self.bytes_out += 1

    async def _release_after(self, delay_ns, generation):
        await Timer(delay_ns, unit="ns")
        self.bus.release(self, generation)

    def is_read(self, command):
        raise NotImplementedError


class FlashModel(ChipModel):
    name = "W25Q128JV"
    read_wait_periods = 4
    has_mode_byte = True

    def __init__(self, dut, bus, image, round_trip_ns=20.0, qe=False):
        super().__init__(dut, bus, dut.cs_flash_n, round_trip_ns, size=32768)
        self.mem[:len(image)] = image[:32768]
        self.qe = bool(qe)

    def program_qe(self, enabled=True):
        """Model the non-volatile bring-up setting; ASIC reset does not call this method."""
        self.qe = bool(enabled)

    def command_allowed(self, command):
        if command == 0xEB and not self.qe:
            self.error("EBh rejected because QE is 0")
            return False
        return True

    def is_read(self, command):
        return True if command == 0xEB else None


class PsramModel(ChipModel):
    name = "APS6404L"
    read_wait_periods = 6
    has_mode_byte = False

    def __init__(self, dut, bus, round_trip_ns=20.0, poison_seed=None):
        super().__init__(dut, bus, dut.cs_ram_n, round_trip_ns, size=32768)
        if poison_seed is not None:
            seed = int(poison_seed) & 0xFF
            for index in range(self.size):
                self.mem[index] = (seed + 73 * index + (index >> 8)) & 0xFF

    def is_read(self, command):
        if command == 0xEB:
            return True
        if command == 0x38:
            return False
        return None

    def min_cs_high_ns(self):
        return T_CPH_NS

    def max_cs_low_ns(self):
        return T_CEM_NS

    def word(self, cpu_addr):
        off = (cpu_addr - 0x8000) & 0x7FFE
        return self.mem[off] | (self.mem[off + 1] << 8)


class BusMonitor:
    """Always-on checks: never both chip selects low; data lanes hold while not driven."""

    def __init__(self, dut):
        self.dut = dut
        self.errors = []
        self._tasks = []

    def start(self):
        self._tasks = [cocotb.start_soon(self._selects()), cocotb.start_soon(self._hold())]

    def stop(self):
        for t in self._tasks:
            t.cancel()
        self._tasks = []

    async def _selects(self):
        while True:
            await First(Edge(self.dut.cs_flash_n), Edge(self.dut.cs_ram_n))
            await ReadOnly()
            flash_n = resolved(self.dut.cs_flash_n)
            ram_n = resolved(self.dut.cs_ram_n)
            if flash_n is None or ram_n is None:
                self.errors.append("a chip select is unresolvable at %.0f ns" % get_sim_time("ns"))
            elif flash_n == 0 and ram_n == 0:
                self.errors.append("both chip selects low at %.0f ns" % get_sim_time("ns"))

    async def _hold(self):
        while True:
            await Edge(self.dut.sd_out)
            await ReadOnly()
            oe = resolved(self.dut.sd_oe)
            if resolved(self.dut.rst_n) == 0:
                continue
            if oe is None:
                self.errors.append("the lane enable is unresolvable at %.0f ns" % get_sim_time("ns"))
            elif oe == 0:
                self.errors.append("data lanes changed while not driven at %.0f ns" % get_sim_time("ns"))
