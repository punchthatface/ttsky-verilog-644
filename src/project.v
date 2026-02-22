/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // All output pins must be assigned. If not used, assign to 0.
    wire error_w;

    // Only uio_out[2] is used as an output; everything else is input
    // Use uio_in[0] for "go" signal and uio_in[1] for "finish" signal
    assign uio_oe  = 8'b00000100;
    assign uio_out = {5'b0, error_w, 2'b0};

    // List all unused inputs to prevent warnings
    wire _unused = &{1'b0, ena, uio_in[7:2], 1'b0};

    RangeFinder #(.WIDTH(8)) u_range_finder (
        .data_in(ui_in),
        .clock(clk),
        .reset(rst_n),
        .go(uio_in[0]),
        .finish(uio_in[1]),
        .range(uo_out),
        .error(error_w)
    );

endmodule
