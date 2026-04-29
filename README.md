![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# TinyDMA-2C

TinyDMA-2C is a two-channel byte DMA engine for Tiny Tapeout. It moves bytes between addresses in an external SPI PSRAM device using a small scheduler, a DMA controller, and a single-bit SPI memory controller.

Tiny Tapeout is an educational shuttle project for fabricating small open-source ASIC designs. This repository contains the RTL, tests, and project metadata for the TinyDMA-2C submission.

The design was built for a `1x2` Tiny Tapeout tile allocation. To fit that target, the submitted build uses 16-bit internal addresses and 8-bit transfer lengths. The PSRAM controller still emits the normal SPI command format with a 24-bit address phase; the upper address byte is driven as zero.

## Interface

Configuration uses `ui_in[7:0]` as a byte-wide command/data bus. `uio_in[0]` is the config-valid strobe, and `uio_in[1]` starts any armed channel.

The external PSRAM connects through UIO pins:

- `uio[2]`: SPI MISO input
- `uio[3]`: SPI chip select output, active low
- `uio[4]`: SPI clock output
- `uio[5]`: SPI MOSI output

Status is reported on `uo_out`, including active/done flags for both DMA channels and configuration adapter status.

More detail is in [docs/info.md](docs/info.md).

## Verification

The project has been tested with:

- cocotb tests for the Tiny Tapeout wrapper and SPI PSRAM model
- RTL simulations for the SPI master, PSRAM controller, DMA subsystem, and top-level DMA path
- FPGA bring-up against a real QSPI PSRAM PMOD
- FPGA tests that drive the actual Tiny Tapeout-style IO wrapper
- UART-driven FPGA scripts covering raw PSRAM access, channel 0 copy, channel 1 fixed-source fill, fixed-destination behavior, zero-length transfer, and a longer 16-byte transfer

The GitHub Actions `test` and `gds` flows have passed for this repository.

## Source

The Tiny Tapeout top module is `tt_um_akim_tinydma` in [src/tt_um_akim_tinydma.v](src/tt_um_akim_tinydma.v). The core RTL is split across the DMA configuration register file, scheduler, controller, SPI master, PSRAM controller, and top-level integration modules in `src/`.
