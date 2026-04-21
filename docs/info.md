## How it works

This project is a two-channel byte DMA engine for Tiny Tapeout. It copies data between addresses in an external SPI PSRAM device using a small internal scheduler and a byte-wide SPI memory controller.

The fixed Tiny Tapeout wrapper is used as follows:

- `ui_in[7:0]`: configuration data byte
- `uio_in[0]`: `cfg_valid` strobe
- `uio_in[1]`: `start` strobe
- `uio_in[2]`: `spi_miso`
- `uio_out[0]`: `spi_clk`
- `uio_out[1]`: `spi_cs_n`
- `uio_out[2]`: `spi_mosi`

A configuration write is sent as two bytes:
1. command byte
2. data byte

Command-byte format:
- bit 7: must be `1` for a write command
- bit 6: channel select (`0` = channel 0, `1` = channel 1)
- bits 5:4: register field (`00`=src, `01`=dst, `10`=len, `11`=ctrl)
- bits 3:2: byte index within the 32-bit register (`00` low byte first)
- bits 1:0: unused, write as `0`

The control low byte uses:
- bit 0: arm channel for next `start`
- bit 1: increment source
- bit 2: increment destination

When `start` is pulsed, any armed channel gets its internal start bit asserted and the DMA begins moving bytes through the SPI PSRAM controller.

## How to test

Example: configure channel 0 to copy 4 bytes from `0x000010` to `0x000020`.

Write the following command/data pairs with `cfg_valid` pulsed for each byte:

- cmd `0x80`, data `0x10`  : ch0 src byte 0
- cmd `0x84`, data `0x00`  : ch0 src byte 1
- cmd `0x88`, data `0x00`  : ch0 src byte 2
- cmd `0x90`, data `0x20`  : ch0 dst byte 0
- cmd `0x94`, data `0x00`  : ch0 dst byte 1
- cmd `0x98`, data `0x00`  : ch0 dst byte 2
- cmd `0xA0`, data `0x04`  : ch0 len byte 0
- cmd `0xA4`, data `0x00`  : ch0 len byte 1
- cmd `0xB0`, data `0x07`  : ch0 ctrl low byte (arm + inc src + inc dst)

Then pulse `start`.

Status outputs:
- `uo_out[0]`: DMA busy
- `uo_out[1]`: done pulse when either channel completes
- `uo_out[2]`: channel 0 done
- `uo_out[3]`: channel 1 done
- `uo_out[4]`: channel 0 active
- `uo_out[5]`: channel 1 active
- `uo_out[6]`: waiting for config data byte
- `uo_out[7]`: invalid config sequence detected

## External hardware

- Tiny Tapeout QSPI PMOD
- APS6404 PSRAM on the PMOD, used in single-bit SPI mode
