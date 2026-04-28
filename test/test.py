# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import re

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


# TT wrapper protocol fields. These mirror project.v / tt_tinydma_cfg_adapter.
FIELD_SRC = 0
FIELD_DST = 1
FIELD_LEN = 2
FIELD_CTRL = 3

# uo_out status bits from project.v
UO_DMA_ACTIVE = 0
UO_DONE_PULSE = 1
UO_CH0_DONE = 2
UO_CH1_DONE = 3
UO_CH0_ACTIVE = 4
UO_CH1_ACTIVE = 5
UO_CFG_PENDING = 6
UO_CFG_ERROR = 7

# uio pin mapping from project.v / info.yaml
UIO_CFG_VALID = 0
UIO_START = 1
UIO_SPI_MISO = 2
UIO_SPI_CS_N = 3
UIO_SPI_CLK = 4
UIO_SPI_MOSI = 5
EXPECTED_UIO_OE = 0x38  # uio[3]=CS#, uio[4]=SCK, uio[5]=MOSI are outputs.


def value_to_int(value) -> int:
    """Return a stable integer from a cocotb value.

    cocotb may print a resolved vector as binary, decimal, or occasionally with
    X/Z/U bits during startup. Decimal-looking strings such as "8" must be
    treated as decimal 8, not as a binary string. Unknown bits are treated as 0
    only when the value is actually a bit-vector string.
    """
    try:
        return int(value)
    except (ValueError, TypeError):
        pass

    value_str = str(value).strip().lower().replace("_", "")
    if value_str == "":
        return 0

    # Resolved decimal representation, e.g. cocotb may stringify a vector as "8".
    if re.fullmatch(r"[0-9]+", value_str):
        return int(value_str, 10)

    # Common explicit bases.
    if value_str.startswith("0x") and re.fullmatch(r"0x[0-9a-fxz]+", value_str):
        cleaned = "0x" + "".join(c if c in "0123456789abcdef" else "0" for c in value_str[2:])
        return int(cleaned, 16)

    if value_str.startswith("0b"):
        value_str = value_str[2:]

    # Bit-vector representation containing possible unknowns.
    bits = []
    for c in value_str:
        if c in "01":
            bits.append(c)
        elif c in "xzuw-":
            bits.append("0")
        else:
            # Ignore formatting characters; fail-safe to 0 for anything else.
            bits.append("0")

    return int("".join(bits), 2) if bits else 0


def get_bit(value, bit: int) -> int:
    return (value_to_int(value) >> bit) & 1


class UioInputDriver:
    """Single shared driver for uio_in.

    The test drives uio_in[0] cfg_valid and uio_in[1] start. The PSRAM model
    drives uio_in[2] miso. A shared shadow prevents one coroutine from
    accidentally clearing another bit.
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

    This is a focused model, not a full PSRAM model. It supports only the
    commands needed by the top-level DMA test:
      0x66 reset-enable
      0x99 reset
      0x02 one-byte write
      0x03 one-byte read
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
                self.addr &= 0x7FFFFF
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
            uio_out_value = value_to_int(self.dut.uio_out.value)
            cs_n = (uio_out_value >> UIO_SPI_CS_N) & 1
            sck = (uio_out_value >> UIO_SPI_CLK) & 1
            mosi = (uio_out_value >> UIO_SPI_MOSI) & 1

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
    assert get_bit(dut.uo_out.value, UO_CFG_PENDING) == 1, "cfg_pending did not assert after command byte"

    await pulse_cfg(dut, uio, data)
    assert get_bit(dut.uo_out.value, UO_CFG_PENDING) == 0, "cfg_pending did not clear after payload byte"


async def write_cfg_word(dut, uio: UioInputDriver, channel: int, field: int, value: int, nbytes: int = 4):
    for byte_idx in range(nbytes):
        await write_cfg_byte(dut, uio, channel, field, byte_idx, (value >> (8 * byte_idx)) & 0xFF)


async def pulse_start(dut, uio: UioInputDriver):
    uio.set_bit(UIO_START, 1)
    await ClockCycles(dut.clk, 1)
    uio.set_bit(UIO_START, 0)
    await ClockCycles(dut.clk, 1)


async def wait_for_condition(dut, condition, message: str, max_cycles: int = 50000):
    for cycle in range(max_cycles):
        await ClockCycles(dut.clk, 1)
        if condition():
            return cycle
    raise AssertionError(message)


async def wait_for_done_pulse(dut, max_cycles: int = 100000):
    return await wait_for_condition(
        dut,
        lambda: get_bit(dut.uo_out.value, UO_DONE_PULSE) == 1,
        f"done pulse not observed; final uo_out=0x{value_to_int(dut.uo_out.value):02x}",
        max_cycles,
    )


@cocotb.test()
async def test_project(dut):
    # Match src/config.json CLOCK_PERIOD = 20 ns / 50 MHz.
    clock = Clock(dut.clk, 20, unit="ns")
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

    uio_oe = value_to_int(dut.uio_oe.value)
    assert uio_oe == EXPECTED_UIO_OE, (
        f"unexpected uio_oe 0x{uio_oe:02x}; expected 0x{EXPECTED_UIO_OE:02x} "
        "for uio[3]=CS#, uio[4]=SCK, uio[5]=MOSI outputs"
    )

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    # Wrapper should flag a malformed command byte where ui_in[7] is not set.
    await pulse_cfg(dut, uio, 0x00)
    assert get_bit(dut.uo_out.value, UO_CFG_ERROR) == 1, "cfg_error did not assert for malformed command"

    # PSRAM controller initialization should produce reset-enable then reset.
    await wait_for_condition(
        dut,
        lambda: len(psram.command_log) >= 2,
        "PSRAM reset sequence was not observed",
        max_cycles=40000,
    )
    assert psram.command_log[0:2] == [0x66, 0x99], f"bad reset command sequence: {psram.command_log[0:2]}"
    assert psram.reset_seen, "PSRAM model never saw reset command"

    # Preload external PSRAM model and run a top-level DMA copy through SPI.
    src = 0x000010
    dst = 0x000020
    pattern = [0xA5, 0x3C, 0x5A, 0xC3]
    for i, value in enumerate(pattern):
        psram.write_mem(src + i, value)
        psram.write_mem(dst + i, 0x00)

    # Channel 0: src=0x10, dst=0x20, len=4, ctrl=arm + inc_src + inc_dst.
    # The TT adapter masks off CTRL bit 0 during config writes and applies it
    # later when uio[1] start is pulsed.
    await write_cfg_word(dut, uio, 0, FIELD_SRC, src, nbytes=3)
    await write_cfg_word(dut, uio, 0, FIELD_DST, dst, nbytes=3)
    await write_cfg_word(dut, uio, 0, FIELD_LEN, len(pattern), nbytes=2)
    await write_cfg_byte(dut, uio, 0, FIELD_CTRL, 0, 0x07)

    assert get_bit(dut.uo_out.value, UO_CFG_ERROR) == 0, "cfg_error remained set after valid config writes"

    reads_before = sum(1 for t in psram.transaction_log if t[0] == "read")
    writes_before = sum(1 for t in psram.transaction_log if t[0] == "write")

    await pulse_start(dut, uio)
    await wait_for_done_pulse(dut)

    assert get_bit(dut.uo_out.value, UO_CH0_DONE) == 1, "channel 0 done flag not set"
    assert get_bit(dut.uo_out.value, UO_CFG_ERROR) == 0, "wrapper error flag asserted during DMA run"

    copied = [psram.read_mem(dst + i) for i in range(len(pattern))]
    source_after = [psram.read_mem(src + i) for i in range(len(pattern))]
    assert copied == pattern, f"destination copy mismatch: expected {pattern}, got {copied}"
    assert source_after == pattern, f"source was modified: expected {pattern}, got {source_after}"

    reads_after = sum(1 for t in psram.transaction_log if t[0] == "read")
    writes_after = sum(1 for t in psram.transaction_log if t[0] == "write")
    assert reads_after - reads_before >= len(pattern), "not enough SPI reads observed for DMA copy"
    assert writes_after - writes_before >= len(pattern), "not enough SPI writes observed for DMA copy"
