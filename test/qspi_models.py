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


class QspiBus:
    """Composes uio_in from the chip that drives the lanes (only one chip is ever selected)."""

    def __init__(self, dut):
        self.dut = dut
        self.release()

    def drive(self, nibble):
        v = 0
        v |= (nibble & 1) << 1
        v |= ((nibble >> 1) & 1) << 2
        v |= ((nibble >> 2) & 1) << 4
        v |= ((nibble >> 3) & 1) << 5
        self.dut.uio_in.value = v

    def drive_x(self):
        self.dut.uio_in.value = LogicArray("00XX0XX0")

    def release(self):
        self.dut.uio_in.value = 0

    def sd_out(self):
        return int(self.dut.sd_out.value)

    def sd_oe(self):
        return int(self.dut.sd_oe.value)


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
            if self.last_cs_rise_ns is not None and t_low - self.last_cs_rise_ns < self.min_cs_high_ns():
                self.error("chip select re-selected after %.1f ns, minimum %.1f" % (t_low - self.last_cs_rise_ns, self.min_cs_high_ns()))
            if int(self.dut.qspi_sck.value) != 0:
                self.error("chip select fell while SCK was high")
            self.selected = True
            self.transactions += 1
            await self.transaction(t_low)

    def min_cs_high_ns(self):
        return T_SHSL_NS

    async def transaction(self, t_low):
        period = 0
        command = 0
        address = 0
        mode = 0
        write_nibbles = []
        data_start = self.data_start_period()
        reading = None
        drive_tasks = []
        while True:
            trig = await First(RisingEdge(self.dut.qspi_sck), FallingEdge(self.dut.qspi_sck), RisingEdge(self.cs))
            now = get_sim_time("ns")
            if trig is RisingEdge(self.cs) or int(self.cs.value) == 1:
                break
            sck = int(self.dut.qspi_sck.value)
            if sck == 1:
                # the chip samples the lanes on the rising edge: setup and hold checks, then decode
                sd = self.bus.sd_out()
                oe = self.bus.sd_oe()
                if self.sd_last_change_ns is not None and now - self.sd_last_change_ns < 5.0 and oe:
                    self.error("data changed %.1f ns before the SCK rising edge of period %d" % (now - self.sd_last_change_ns, period))
                if period < 8:
                    if oe != 0b0001:
                        self.error("command period %d drives lanes %s, expected 0001" % (period, format(oe, "04b")))
                    command = ((command << 1) | (sd & 1)) & 0xFF
                    if period == 7:
                        self.commands.append(command)
                        reading = self.is_read(command)
                        if reading is None:
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
                    self._tasks.append(cocotb.start_soon(self._drive_nibble(address, nib_index, now)))
                period += 1
        t_high = get_sim_time("ns")
        self.transaction_bytes.append(self.bytes_out - sum(self.transaction_bytes))
        self.last_cs_rise_ns = t_high
        self.cs_low_max_ns = max(self.cs_low_max_ns, t_high - t_low)
        if t_high - t_low > self.max_cs_low_ns():
            self.error("chip select low for %.0f ns, maximum %.0f" % (t_high - t_low, self.max_cs_low_ns()))
        if int(self.dut.qspi_sck.value) != 0:
            self.error("chip select rose while SCK was high")
        self.selected = False
        cocotb.start_soon(self._release_after(self.round_trip / 2 + 7.0))

    def max_cs_low_ns(self):
        return 1e12

    async def _drive_nibble(self, address, nib_index, t_fall):
        """Drive X then the nibble on the lanes, delayed by the round trip; only while selected."""
        await Timer(self.round_trip + T_CLQX_NS, unit="ns")
        if not self.selected:
            return
        self.bus.drive_x()
        await Timer(T_CLQV_NS - T_CLQX_NS, unit="ns")
        if not self.selected:
            return
        byte = self.mem[(address + nib_index // 2) % self.size]
        nibble = (byte >> 4) & 0xF if nib_index % 2 == 0 else byte & 0xF
        self.bus.drive(nibble)
        if nib_index % 2 == 1:
            self.bytes_out += 1

    async def _release_after(self, delay_ns):
        await Timer(delay_ns, unit="ns")
        if not self.selected:
            self.bus.release()

    def is_read(self, command):
        raise NotImplementedError


class FlashModel(ChipModel):
    name = "W25Q128JV"
    read_wait_periods = 4
    has_mode_byte = True

    def __init__(self, dut, bus, image, round_trip_ns=20.0):
        super().__init__(dut, bus, dut.cs_flash_n, round_trip_ns, size=32768)
        self.mem[:len(image)] = image[:32768]

    def is_read(self, command):
        return True if command == 0xEB else None


class PsramModel(ChipModel):
    name = "APS6404L"
    read_wait_periods = 6
    has_mode_byte = False

    def __init__(self, dut, bus, round_trip_ns=20.0):
        super().__init__(dut, bus, dut.cs_ram_n, round_trip_ns, size=32768)

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
            if int(self.dut.cs_flash_n.value) == 0 and int(self.dut.cs_ram_n.value) == 0:
                self.errors.append("both chip selects low at %.0f ns" % get_sim_time("ns"))

    async def _hold(self):
        while True:
            await Edge(self.dut.sd_out)
            await ReadOnly()
            if int(self.dut.sd_oe.value) == 0:
                self.errors.append("data lanes changed while not driven at %.0f ns" % get_sim_time("ns"))
