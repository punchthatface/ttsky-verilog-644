/*
 * Tiny Tapeout wrapper for TinyDMA.
 *
 * tt_um_akim_tinydma owns only the TT pin wiring and module instances.
 * tt_tinydma_cfg_adapter contains the TT-specific byte-stream config protocol.
 */

`default_nettype none

module tt_um_akim_tinydma (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // TT pin decode
    wire cfg_valid = uio_in[0];
    wire start     = uio_in[1];
    wire spi_miso  = uio_in[2];

    // Core config bus
    logic        cfg_we;
    logic        cfg_re;
    logic [2:0]  cfg_addr;
    logic [31:0] cfg_wdata;
    logic [31:0] cfg_rdata;

    // Core status
    logic        dma_busy;
    logic [1:0]  chan_active;
    logic [1:0]  chan_done;

    // PSRAM SPI signals
    logic spi_clk;
    logic spi_cs_n;
    logic spi_mosi;

    tt_tinydma_cfg_adapter u_tt_tinydma_cfg_adapter (
      .clk        (clk),
      .rst_n      (rst_n),

      .ui_in      (ui_in),
      .cfg_valid  (cfg_valid),
      .start      (start),

      .cfg_we     (cfg_we),
      .cfg_re     (cfg_re),
      .cfg_addr   (cfg_addr),
      .cfg_wdata  (cfg_wdata),
      .cfg_rdata  (cfg_rdata),

      .dma_busy   (dma_busy),
      .chan_active(chan_active),
      .chan_done  (chan_done),

      .uo_out     (uo_out)
    );

    tinydma_top #(
      .PSRAM_RESET_CYCLES(20000),
      .PSRAM_RESET_RECOVERY_CYCLES(8)
    ) u_tinydma_top (
      .clk          (clk),
      .rst_n        (rst_n),
      .cfg_we       (cfg_we),
      .cfg_re       (cfg_re),
      .cfg_addr     (cfg_addr),
      .cfg_wdata    (cfg_wdata),
      .cfg_rdata    (cfg_rdata),
      .dma_busy     (dma_busy),
      .chan_active_o(chan_active),
      .chan_done_o  (chan_done),
      .spi_clk      (spi_clk),
      .spi_cs_n     (spi_cs_n),
      .spi_mosi     (spi_mosi),
      .spi_miso     (spi_miso)
    );

    // TT UIO pin assignment:
    //   uio[0] = cfg_valid input
    //   uio[1] = start input
    //   uio[2] = spi_miso input
    //   uio[3] = spi_cs_n output
    //   uio[4] = spi_clk output
    //   uio[5] = spi_mosi output
    //   uio[6] = unused input
    //   uio[7] = unused input
    assign uio_out = {2'b00, spi_mosi, spi_clk, spi_cs_n, 3'b000};
    assign uio_oe  = 8'b0011_1000;

    wire _unused = &{1'b0, ena, uio_in[7:6], 1'b0};

endmodule


// Helper module to adapt the TT byte-stream config protocol to the
// DMA core's register-based config interface.
// Basically a little hack that allows us to mimic real DMA interface with the
// limited TT pinout.
module tt_tinydma_cfg_adapter (
    input  wire        clk,
    input  wire        rst_n,

    // TT-side config controls
    input  wire [7:0]  ui_in,
    input  wire        cfg_valid,
    input  wire        start,

    // Core config bus
    output logic       cfg_we,
    output logic       cfg_re,
    output logic [2:0] cfg_addr,
    output logic [31:0] cfg_wdata,
    input  wire [31:0] cfg_rdata,

    // Core status
    input  wire        dma_busy,
    input  wire [1:0]  chan_active,
    input  wire [1:0]  chan_done,

    // TT outputs
    output logic [7:0] uo_out
);

    localparam logic [1:0] FIELD_SRC  = 2'd0;
    localparam logic [1:0] FIELD_DST  = 2'd1;
    localparam logic [1:0] FIELD_LEN  = 2'd2;
    localparam logic [1:0] FIELD_CTRL = 2'd3;

    logic [31:0] reg0_shadow;
    logic [31:0] reg1_shadow;
    logic [31:0] reg2_shadow;
    logic [31:0] reg3_shadow;
    logic [31:0] reg4_shadow;
    logic [31:0] reg5_shadow;
    logic [31:0] reg6_shadow;
    logic [31:0] reg7_shadow;

    logic        ch0_arm;
    logic        ch1_arm;

    logic        pending_data;
    logic [2:0]  pending_reg_addr;
    logic [1:0]  pending_byte_idx;
    logic        error_flag;

    logic        start_pending_ch0;
    logic        start_pending_ch1;

    logic [1:0]  chan_done_d;
    logic        done_pulse;

    function automatic [2:0] cmd_to_reg_addr(
      input logic       channel,
      input logic [1:0] field
    );
      begin
        cmd_to_reg_addr = {channel, field};
      end
    endfunction

    function automatic [31:0] update_byte(
      input logic [31:0] original,
      input logic [1:0]  byte_idx,
      input logic [7:0]  byte_value
    );
      begin
        update_byte = original;
        case (byte_idx)
          2'd0: update_byte[7:0]   = byte_value;
          2'd1: update_byte[15:8]  = byte_value;
          2'd2: update_byte[23:16] = byte_value;
          2'd3: update_byte[31:24] = byte_value;
          default: begin
          end
        endcase
      end
    endfunction

    always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) begin
        reg0_shadow       <= 32'h0000_0000;
        reg1_shadow       <= 32'h0000_0000;
        reg2_shadow       <= 32'h0000_0000;
        reg3_shadow       <= 32'h0000_0000;
        reg4_shadow       <= 32'h0000_0000;
        reg5_shadow       <= 32'h0000_0000;
        reg6_shadow       <= 32'h0000_0000;
        reg7_shadow       <= 32'h0000_0000;
        ch0_arm           <= 1'b0;
        ch1_arm           <= 1'b0;
        pending_data      <= 1'b0;
        pending_reg_addr  <= 3'b000;
        pending_byte_idx  <= 2'b00;
        error_flag        <= 1'b0;
        start_pending_ch0 <= 1'b0;
        start_pending_ch1 <= 1'b0;
        cfg_we            <= 1'b0;
        cfg_re            <= 1'b0;
        cfg_addr          <= 3'b000;
        cfg_wdata         <= 32'h0000_0000;
        chan_done_d       <= 2'b00;
        done_pulse        <= 1'b0;
      end else begin
        cfg_we      <= 1'b0;
        cfg_re      <= 1'b0;
        done_pulse  <= (chan_done & ~chan_done_d) != 2'b00;
        chan_done_d <= chan_done;

        if (start) begin
          if (ch0_arm) begin
            start_pending_ch0 <= 1'b1;
          end
          if (ch1_arm) begin
            start_pending_ch1 <= 1'b1;
          end
        end

        if (cfg_valid) begin
          error_flag <= 1'b0;

          if (!pending_data) begin
            if (ui_in[7]) begin
              pending_reg_addr <= cmd_to_reg_addr(ui_in[6], ui_in[5:4]);
              pending_byte_idx <= ui_in[3:2];
              pending_data     <= 1'b1;
            end else begin
              error_flag <= 1'b1;
            end
          end else begin
            pending_data <= 1'b0;
            cfg_we       <= 1'b1;
            cfg_addr     <= pending_reg_addr;

            case (pending_reg_addr)
              3'd0: begin
                reg0_shadow <= update_byte(reg0_shadow, pending_byte_idx, ui_in);
                cfg_wdata   <= update_byte(reg0_shadow, pending_byte_idx, ui_in);
              end

              3'd1: begin
                reg1_shadow <= update_byte(reg1_shadow, pending_byte_idx, ui_in);
                cfg_wdata   <= update_byte(reg1_shadow, pending_byte_idx, ui_in);
              end

              3'd2: begin
                reg2_shadow <= update_byte(reg2_shadow, pending_byte_idx, ui_in);
                cfg_wdata   <= update_byte(reg2_shadow, pending_byte_idx, ui_in);
              end

              3'd3: begin
                reg3_shadow <= update_byte(reg3_shadow, pending_byte_idx, {ui_in[7:1], 1'b0});
                cfg_wdata   <= update_byte(reg3_shadow, pending_byte_idx, {ui_in[7:1], 1'b0});
                if (pending_byte_idx == 2'd0) begin
                  ch0_arm <= ui_in[0];
                end
              end

              3'd4: begin
                reg4_shadow <= update_byte(reg4_shadow, pending_byte_idx, ui_in);
                cfg_wdata   <= update_byte(reg4_shadow, pending_byte_idx, ui_in);
              end

              3'd5: begin
                reg5_shadow <= update_byte(reg5_shadow, pending_byte_idx, ui_in);
                cfg_wdata   <= update_byte(reg5_shadow, pending_byte_idx, ui_in);
              end

              3'd6: begin
                reg6_shadow <= update_byte(reg6_shadow, pending_byte_idx, ui_in);
                cfg_wdata   <= update_byte(reg6_shadow, pending_byte_idx, ui_in);
              end

              3'd7: begin
                reg7_shadow <= update_byte(reg7_shadow, pending_byte_idx, {ui_in[7:1], 1'b0});
                cfg_wdata   <= update_byte(reg7_shadow, pending_byte_idx, {ui_in[7:1], 1'b0});
                if (pending_byte_idx == 2'd0) begin
                  ch1_arm <= ui_in[0];
                end
              end

              default: begin
                cfg_wdata <= 32'h0000_0000;
              end
            endcase
          end
        end else if (start_pending_ch0) begin
          cfg_we            <= 1'b1;
          cfg_addr          <= 3'd3;
          cfg_wdata         <= reg3_shadow | 32'h0000_0001;
          start_pending_ch0 <= 1'b0;
        end else if (start_pending_ch1) begin
          cfg_we            <= 1'b1;
          cfg_addr          <= 3'd7;
          cfg_wdata         <= reg7_shadow | 32'h0000_0001;
          start_pending_ch1 <= 1'b0;
        end
      end
    end

    always_comb begin
      uo_out    = 8'h00;
      uo_out[0] = chan_active[0] | chan_active[1];
      uo_out[1] = done_pulse;
      uo_out[2] = chan_done[0];
      uo_out[3] = chan_done[1];
      uo_out[4] = chan_active[0];
      uo_out[5] = chan_active[1];
      uo_out[6] = pending_data;
      uo_out[7] = error_flag;
    end

    wire _unused = &{1'b0, dma_busy, cfg_rdata, FIELD_SRC, FIELD_DST, FIELD_LEN, FIELD_CTRL, 1'b0};

endmodule

`default_nettype wire
