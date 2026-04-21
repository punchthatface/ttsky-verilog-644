# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


def set_uio_bit(value: int, bit: int, bitval: int) -> int:
    if bitval:
        return value | (1 << bit)
    return value & ~(1 << bit)


async def pulse_cfg(dut, data: int):
    dut.ui_in.value = data
    dut.uio_in.value = set_uio_bit(int(dut.uio_in.value), 0, 1)
    await ClockCycles(dut.clk, 1)
    dut.uio_in.value = set_uio_bit(int(dut.uio_in.value), 0, 0)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 1)


async def write_cfg_byte(dut, channel: int, field: int, byte_idx: int, data: int):
    cmd = 0x80 | ((channel & 1) << 6) | ((field & 0x3) << 4) | ((byte_idx & 0x3) << 2)
    await pulse_cfg(dut, cmd)
    await pulse_cfg(dut, data)


async def pulse_start(dut):
    dut.uio_in.value = set_uio_bit(int(dut.uio_in.value), 1, 1)
    await ClockCycles(dut.clk, 1)
    dut.uio_in.value = set_uio_bit(int(dut.uio_in.value), 1, 0)


@cocotb.test()
async def test_project(dut):
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    await ClockCycles(dut.clk, 40)

    # Program channel 0 for a 4-byte incrementing transfer.
    await write_cfg_byte(dut, 0, 0, 0, 0x10)
    await write_cfg_byte(dut, 0, 0, 1, 0x00)
    await write_cfg_byte(dut, 0, 0, 2, 0x00)
    await write_cfg_byte(dut, 0, 1, 0, 0x20)
    await write_cfg_byte(dut, 0, 1, 1, 0x00)
    await write_cfg_byte(dut, 0, 1, 2, 0x00)
    await write_cfg_byte(dut, 0, 2, 0, 0x04)
    await write_cfg_byte(dut, 0, 2, 1, 0x00)
    await write_cfg_byte(dut, 0, 3, 0, 0x07)

    await pulse_start(dut)

    for _ in range(2000):
        await ClockCycles(dut.clk, 1)
        if (int(dut.uo_out.value) >> 1) & 1:
            break
    else:
        assert False, "done pulse not observed"

    assert ((int(dut.uo_out.value) >> 7) & 1) == 0, "wrapper error flag asserted"
