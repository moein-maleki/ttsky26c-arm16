"""Pure model lifecycle controls that do not require an HDL simulator."""

import inspect

import qspi_models


class Signal:
    def __init__(self, value=0):
        self.value = value


class Dut:
    def __init__(self):
        self.uio_in = Signal()
        self.cs_flash_n = Signal(1)
        self.cs_ram_n = Signal(1)


def test_stale_generation_cannot_drive_reselected_flash():
    """Removing the generation check must let an old delayed writer change the bus."""
    dut = Dut()
    bus = qspi_models.QspiBus(dut)
    owner = object()
    assert hasattr(bus, "begin"), "QSPI bus has no transaction ownership"
    assert bus.begin(owner, 1)
    assert bus.end(owner, 1)
    assert bus.begin(owner, 2)
    assert bus.drive(0x5, owner, 2)
    before = int(dut.uio_in.value)
    assert not bus.drive(0xA, owner, 1)
    assert int(dut.uio_in.value) == before


def test_old_chip_release_cannot_clear_new_chip_drive():
    """Removing owner-bound release must let flash clear the active PSRAM value."""
    dut = Dut()
    bus = qspi_models.QspiBus(dut)
    flash = object()
    psram = object()
    assert hasattr(bus, "begin"), "QSPI bus has no transaction ownership"
    assert bus.begin(flash, 7)
    assert bus.drive(0xA, flash, 7)
    assert bus.end(flash, 7)
    assert bus.begin(psram, 3)
    assert bus.drive(0x5, psram, 3)
    before = int(dut.uio_in.value)
    assert not bus.release(flash, 7)
    assert int(dut.uio_in.value) == before


def test_psram_poison_is_repeatable_and_not_zero_filled():
    """Removing cold-memory poison must restore the false all-zero power-up assumption."""
    assert "poison_seed" in inspect.signature(qspi_models.PsramModel).parameters, \
        "PSRAM model has no deterministic cold-memory poison"
    first = qspi_models.PsramModel(Dut(), qspi_models.QspiBus(Dut()), poison_seed=23)
    second = qspi_models.PsramModel(Dut(), qspi_models.QspiBus(Dut()), poison_seed=23)
    assert first.mem[:16] == second.mem[:16]
    assert first.mem[:16] != bytes(16)
