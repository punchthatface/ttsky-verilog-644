/*
 * Tiny Tapeout wrapper for TinyDMA.
 * Fixed TT header, byte-stream configuration protocol inside.
 */

`default_nettype none

module tt_um_akim_tinydma #(
    parameter int PSRAM_RESET_CYCLES          = 20000,
    parameter int PSRAM_RESET_RECOVERY_CYCLES = 8
) (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    localparam logic [1:0] FIELD_SRC  = 2'd0;
    localparam logic [1:0] FIELD_DST  = 2'd1;
    localparam logic [1:0] FIELD_LEN  = 2'd2;
    localparam logic [1:0] FIELD_CTRL = 2'd3;

    logic cfg_we;
    logic cfg_re;
    logic [$clog2(N_CH*4)-1:0] cfg_addr;
    logic [31:0] cfg_wdata;
    logic [31:0] cfg_rdata;

    logic dma_busy;
    logic [N_CH-1:0] chan_active;
    logic [N_CH-1:0] chan_done;

    logic spi_clk;
    logic spi_cs_n;
    logic spi_mosi;

    logic [31:0] reg0_shadow, reg1_shadow, reg2_shadow, reg3_shadow;
    logic [31:0] reg4_shadow, reg5_shadow, reg6_shadow, reg7_shadow;
    logic        ch0_arm, ch1_arm;

    logic        pending_data;
    logic [2:0]  pending_reg_addr;
    logic [1:0]  pending_byte_idx;
    logic        error_flag;

    logic        start_pending_ch0;
    logic        start_pending_ch1;

    logic [N_CH-1:0] chan_done_d;
    logic            done_pulse;

    logic [7:0] uo_out_r;
    logic [7:0] uio_out_r;
    logic [7:0] uio_oe_r;

    wire cfg_valid = uio_in[0];
    wire start     = uio_in[1];
    wire spi_miso  = uio_in[2];

    wire _unused = &{1'b0, ena, uio_in[7:3], 1'b0};

    tinydma_top #(
      .PSRAM_RESET_CYCLES(PSRAM_RESET_CYCLES),
      .PSRAM_RESET_RECOVERY_CYCLES(PSRAM_RESET_RECOVERY_CYCLES)
    ) u_tinydma_top (
      .clk         (clk),
      .rst_n       (rst_n),
      .cfg_we      (cfg_we),
      .cfg_re      (cfg_re),
      .cfg_addr    (cfg_addr),
      .cfg_wdata   (cfg_wdata),
      .cfg_rdata   (cfg_rdata),
      .dma_busy    (dma_busy),
      .chan_active_o(chan_active),
      .chan_done_o (chan_done),
      .spi_clk     (spi_clk),
      .spi_cs_n    (spi_cs_n),
      .spi_mosi    (spi_mosi),
      .spi_miso    (spi_miso)
    );

    function automatic [2:0] cmd_to_reg_addr(
      input logic channel,
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

    always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        reg0_shadow      <= 32'h0000_0000;
        reg1_shadow      <= 32'h0000_0000;
        reg2_shadow      <= 32'h0000_0000;
        reg3_shadow      <= 32'h0000_0000;
        reg4_shadow      <= 32'h0000_0000;
        reg5_shadow      <= 32'h0000_0000;
        reg6_shadow      <= 32'h0000_0000;
        reg7_shadow      <= 32'h0000_0000;
        ch0_arm          <= 1'b0;
        ch1_arm          <= 1'b0;
        pending_data     <= 1'b0;
        pending_reg_addr <= 3'b000;
        pending_byte_idx <= 2'b00;
        error_flag       <= 1'b0;
        start_pending_ch0 <= 1'b0;
        start_pending_ch1 <= 1'b0;
        cfg_we           <= 1'b0;
        cfg_re           <= 1'b0;
        cfg_addr         <= '0;
        cfg_wdata        <= 32'h0000_0000;
        chan_done_d      <= '0;
        done_pulse       <= 1'b0;
      end else begin
        cfg_we      <= 1'b0;
        cfg_re      <= 1'b0;
        done_pulse  <= (chan_done & ~chan_done_d) != '0;
        chan_done_d <= chan_done;

        if (start) begin
          if (ch0_arm) start_pending_ch0 <= 1'b1;
          if (ch1_arm) start_pending_ch1 <= 1'b1;
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
      uo_out_r      = 8'h00;
      uio_out_r     = 8'h00;
      uio_oe_r      = 8'h00;

      uio_out_r[0]  = spi_clk;
      uio_out_r[1]  = spi_cs_n;
      uio_out_r[2]  = spi_mosi;
      uio_oe_r[2:0] = 3'b111;

      uo_out_r[0]   = chan_active[0] | chan_active[1];
      uo_out_r[1]   = done_pulse;
      uo_out_r[2]   = chan_done[0];
      uo_out_r[3]   = chan_done[1];
      uo_out_r[4]   = chan_active[0];
      uo_out_r[5]   = chan_active[1];
      uo_out_r[6]   = pending_data;
      uo_out_r[7]   = error_flag;
    end

    assign uo_out  = uo_out_r;
    assign uio_out = uio_out_r;
    assign uio_oe  = uio_oe_r;

endmodule

