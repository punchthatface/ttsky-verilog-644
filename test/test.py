# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


# TT wrapper protocol fields. These mirror project.v / tt_tinydma_cfg_adapter.
FIELD_SRC = 0
FIELD_DST = 1
FIELD_LEN = 2
FIELD_CTRL = 3

UO_DMA_ACTIVE = 0
UO_DONE_PULSE = 1
UO_CH0_DONE = 2
UO_CH1_DONE = 3
UO_CH0_ACTIVE = 4
UO_CH1_ACTIVE = 5
UO_CFG_PENDING = 6
UO_CFG_ERROR = 7

UIO_CFG_VALID = 0
UIO_START = 1
UIO_SPI_MISO = 2
UIO_SPI_CS_N = 3
UIO_SPI_CLK = 4
UIO_SPI_MOSI = 5


def get_bit(value, bit: int) -> int:
    return (int(value) >> bit) & 1


class UioInputDriver:
    """Shared driver for uio_in bits.

    The cocotb test uses uio_in[0] and uio_in[1] for cfg_valid/start.
    The PSRAM model concurrently drives uio_in[2] as spi_miso.
    This object keeps a single shadow value so the coroutines do not stomp each
    other when updating different bits.
    """

    def __init__(self, dut):
        self.dut = dut
        self.value = 0
        self.apply()

    def apply(self):
        self.dut.uio_in.value = self.value

    def set_bit(self, bit: int, bitval: int):
        if bitval:
            self.value |= 1 << bit
        else:
            self.value &= ~(1 << bit)
        self.apply()


class SpiPsramModel:
    """Small external SPI PSRAM model for the TT wrapper test.

    This is intentionally not cycle-accurate. It models only the commands the
    top-level DMA test needs:
      0x66 reset-enable
      0x99 reset
      0x02 single-byte write
      0x03 single-byte read

    The model observes the real TT pins:
      uio_out[3] = CS#
      uio_out[4] = SCK
      uio_out[5] = MOSI
    and drives:
      uio_in[2]  = MISO
    """

    def __init__(self, dut, uio_driver: UioInputDriver):
        self.dut = dut
        self.uio = uio_driver
        self.mem = {}
        self.command_log = []
        self.transaction_log = []
        self.reset_seen = False

        self.state = "IDLE"
        self.cmd = 0
        self.addr = 0
        self.bit_count = 0
        self.write_data = 0
        self.read_data = 0
        self.read_bit_idx = 0
        self.prev_cs_n = 1
        self.prev_sck = 0

    def read_mem(self, addr: int) -> int:
        return self.mem.get(addr & 0x7FFFFF, 0)

    def write_mem(self, addr: int, data: int):
        self.mem[addr & 0x7FFFFF] = data & 0xFF

    def _start_transaction(self):
        self.state = "CMD"
        self.cmd = 0
        self.addr = 0
        self.bit_count = 0
        self.write_data = 0
        self.read_data = 0
        self.read_bit_idx = 0
        self.uio.set_bit(UIO_SPI_MISO, 0)

    def _end_transaction(self):
        self.state = "IDLE"
        self.bit_count = 0
        self.uio.set_bit(UIO_SPI_MISO, 0)

    def _on_sck_rising(self, mosi: int):
        if self.state == "CMD":
            self.cmd = ((self.cmd << 1) | mosi) & 0xFF
            self.bit_count += 1
            if self.bit_count == 8:
                self.command_log.append(self.cmd)
                self.bit_count = 0

                if self.cmd == 0x66:
                    self.state = "IGNORE"
                elif self.cmd == 0x99:
                    self.reset_seen = True
                    self.state = "IGNORE"
                elif self.cmd in (0x02, 0x03):
                    self.addr = 0
                    self.state = "ADDR"
                else:
                    self.state = "IGNORE"

        elif self.state == "ADDR":
            self.addr = ((self.addr << 1) | mosi) & 0xFFFFFF
            self.bit_count += 1
            if self.bit_count == 24:
                self.bit_count = 0
                self.addr &= 0x7FFFFF  # APS6404 address space is A[22:0].
                if self.cmd == 0x02:
                    self.write_data = 0
                    self.state = "WRITE_DATA"
                else:
                    self.read_data = self.read_mem(self.addr)
                    self.read_bit_idx = 0
                    self.transaction_log.append(("read", self.addr, self.read_data))
                    self.state = "READ_DATA"

        elif self.state == "WRITE_DATA":
            self.write_data = ((self.write_data << 1) | mosi) & 0xFF
            self.bit_count += 1
            if self.bit_count == 8:
                self.write_mem(self.addr, self.write_data)
                self.transaction_log.append(("write", self.addr, self.write_data))
                self.bit_count = 0
                self.state = "IGNORE"

        # READ_DATA ignores MOSI dummy bits.

    def _on_sck_falling(self):
        if self.state == "READ_DATA" and self.read_bit_idx < 8:
            bit = (self.read_data >> (7 - self.read_bit_idx)) & 1
            self.uio.set_bit(UIO_SPI_MISO, bit)
            self.read_bit_idx += 1
        else:
            self.uio.set_bit(UIO_SPI_MISO, 0)

    async def run(self):
        while True:
            await RisingEdge(self.dut.clk)
            uio_out = int(self.dut.uio_out.value)
            cs_n = get_bit(uio_out, UIO_SPI_CS_N)
            sck = get_bit(uio_out, UIO_SPI_CLK)
            mosi = get_bit(uio_out, UIO_SPI_MOSI)

            if self.prev_cs_n == 1 and cs_n == 0:
                self._start_transaction()
            elif self.prev_cs_n == 0 and cs_n == 1:
                self._end_transaction()

            if cs_n == 0:
                if self.prev_sck == 0 and sck == 1:
                    self._on_sck_rising(mosi)
                elif self.prev_sck == 1 and sck == 0:
                    self._on_sck_falling()

            self.prev_cs_n = cs_n
            self.prev_sck = sck


async def pulse_cfg(dut, uio: UioInputDriver, data: int):
    dut.ui_in.value = data & 0xFF
    uio.set_bit(UIO_CFG_VALID, 1)
    await ClockCycles(dut.clk, 1)
    uio.set_bit(UIO_CFG_VALID, 0)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 1)


async def write_cfg_byte(dut, uio: UioInputDriver, channel: int, field: int, byte_idx: int, data: int):
    cmd = 0x80 | ((channel & 1) << 6) | ((field & 0x3) << 4) | ((byte_idx & 0x3) << 2)
    await pulse_cfg(dut, uio, cmd)

    # After a valid command byte, the wrapper should expose cfg_pending.
    assert get_bit(dut.uo_out.value, UO_CFG_PENDING) == 1, "cfg_pending did not assert after command byte"

    await pulse_cfg(dut, uio, data)

    # After the payload byte, cfg_pending should clear.
    assert get_bit(dut.uo_out.value, UO_CFG_PENDING) == 0, "cfg_pending did not clear after payload byte"


async def write_cfg_word(dut, uio: UioInputDriver, channel: int, field: int, value: int, nbytes: int = 4):
    for byte_idx in range(nbytes):
        await write_cfg_byte(dut, uio, channel, field, byte_idx, (value >> (8 * byte_idx)) & 0xFF)


async def pulse_start(dut, uio: UioInputDriver):
    uio.set_bit(UIO_START, 1)
    await ClockCycles(dut.clk, 1)
    uio.set_bit(UIO_START, 0)
    await ClockCycles(dut.clk, 1)


async def wait_for_done_pulse(dut, max_cycles: int = 50000):
    for _ in range(max_cycles):
        await ClockCycles(dut.clk, 1)
        if get_bit(dut.uo_out.value, UO_DONE_PULSE):
            return
    raise AssertionError("done pulse not observed")


async def wait_for_condition(dut, condition, message: str, max_cycles: int = 50000):
    for _ in range(max_cycles):
        await ClockCycles(dut.clk, 1)
        if condition():
            return
    raise AssertionError(message)


@cocotb.test()
async def test_project(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    uio = UioInputDriver(dut)
    psram = SpiPsramModel(dut, uio)
    cocotb.start_soon(psram.run())

    dut.ena.value = 1
    dut.ui_in.value = 0
    uio.value = 0
    uio.apply()
    dut.rst_n.value = 0

    await ClockCycles(dut.clk, 10)

    # Check fixed UIO directions: uio[3]=CS#, uio[4]=SCK, uio[5]=MOSI are outputs.
    assert int(dut.uio_oe.value) == 0x38, f"unexpected uio_oe: 0x{int(dut.uio_oe.value):02x}"

    dut.rst_n.value = 1

    # Wrapper should flag a malformed command byte where ui_in[7] is not set.
    await pulse_cfg(dut, uio, 0x00)
    assert get_bit(dut.uo_out.value, UO_CFG_ERROR) == 1, "cfg_error did not assert for malformed command"

    # Wait for PSRAM controller initialization. It should send 0x66 then 0x99.
    await wait_for_condition(
        dut,
        lambda: len(psram.command_log) >= 2,
        "PSRAM reset sequence was not observed",
        max_cycles=25000,
    )
    assert psram.command_log[0:2] == [0x66, 0x99], f"bad reset command sequence: {psram.command_log[0:2]}"
    assert psram.reset_seen, "PSRAM model never saw reset command"

    # Preload external PSRAM model and run a real top-level DMA copy through SPI.
    src = 0x000010
    dst = 0x000020
    pattern = [0xA5, 0x3C, 0x5A, 0xC3]
    for i, value in enumerate(pattern):
        psram.write_mem(src + i, value)
        psram.write_mem(dst + i, 0x00)

    # Channel 0: src=0x10, dst=0x20, len=4, ctrl=arm/start + inc_src + inc_dst.
    await write_cfg_word(dut, uio, 0, FIELD_SRC, src, nbytes=3)
    await write_cfg_word(dut, uio, 0, FIELD_DST, dst, nbytes=3)
    await write_cfg_word(dut, uio, 0, FIELD_LEN, len(pattern), nbytes=2)
    await write_cfg_byte(dut, uio, 0, FIELD_CTRL, 0, 0x07)

    # The valid command above should also clear the earlier malformed-command error.
    assert get_bit(dut.uo_out.value, UO_CFG_ERROR) == 0, "cfg_error remained set after valid config writes"

    await pulse_start(dut, uio)
    await wait_for_done_pulse(dut)

    assert get_bit(dut.uo_out.value, UO_CH0_DONE) == 1, "channel 0 done flag not set"
    assert get_bit(dut.uo_out.value, UO_CFG_ERROR) == 0, "wrapper error flag asserted during DMA run"

    copied = [psram.read_mem(dst + i) for i in range(len(pattern))]
    source_after = [psram.read_mem(src + i) for i in range(len(pattern))]
    assert copied == pattern, f"destination copy mismatch: expected {pattern}, got {copied}"
    assert source_after == pattern, f"source was modified: expected {pattern}, got {source_after}"

    # Sanity-check that SPI traffic really happened through the model.
    assert any(t[0] == "read" for t in psram.transaction_log), "no SPI reads observed"
    assert any(t[0] == "write" for t in psram.transaction_log), "no SPI writes observed"
