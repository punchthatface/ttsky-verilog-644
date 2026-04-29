import dma_pkg::*;

module cfg_reg #(
  parameter int N_REGS_PER_CH = 4
) (
  // Clock and active-low reset.
  input  logic                                   clk,
  input  logic                                   rst_n,

  // Simple register access port.
  input  logic                                   cfg_we,
  input  logic                                   cfg_re,
  input  logic [$clog2(N_CH*N_REGS_PER_CH)-1:0] cfg_addr,
  input  logic [31:0]                            cfg_wdata,
  output logic [31:0]                            cfg_rdata,

  // Runtime status/control handshake from the DMA controller.
  input  logic [N_CH-1:0]                        start_clear,
  input  logic [N_CH-1:0]                        chan_active,
  input  logic [N_CH-1:0]                        chan_done,

  // Channel 0 decoded configuration.
  output logic [ADDR_W-1:0]                      cfg0_src_base,
  output logic [ADDR_W-1:0]                      cfg0_dst_base,
  output logic [LEN_W-1:0]                       cfg0_len,
  output logic                                   cfg0_inc_src,
  output logic                                   cfg0_inc_dst,
  output logic                                   cfg0_start_en,

  // Channel 1 decoded configuration.
  output logic [ADDR_W-1:0]                      cfg1_src_base,
  output logic [ADDR_W-1:0]                      cfg1_dst_base,
  output logic [LEN_W-1:0]                       cfg1_len,
  output logic                                   cfg1_inc_src,
  output logic                                   cfg1_inc_dst,
  output logic                                   cfg1_start_en
);

  localparam int REG_SRC  = 0;
  localparam int REG_DST  = 1;
  localparam int REG_LEN  = 2;
  localparam int REG_CTRL = 3;

  // Address map per channel:
  //   0: source base, 1: destination base, 2: length, 3: control/status.
  logic channel_sel;
  logic [1:0] reg_sel;

  assign channel_sel = cfg_addr[2];
  assign reg_sel     = cfg_addr[1:0];

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      cfg0_src_base <= '0;
      cfg0_dst_base <= '0;
      cfg0_len      <= '0;
      cfg0_inc_src  <= 1'b0;
      cfg0_inc_dst  <= 1'b0;
      cfg0_start_en <= 1'b0;
      cfg1_src_base <= '0;
      cfg1_dst_base <= '0;
      cfg1_len      <= '0;
      cfg1_inc_src  <= 1'b0;
      cfg1_inc_dst  <= 1'b0;
      cfg1_start_en <= 1'b0;
    end else begin
      // The controller pulses start_clear once it has accepted a channel.
      // This turns the start bit into a request latch instead of a sticky bit.
      if (start_clear[0]) cfg0_start_en <= 1'b0;
      if (start_clear[1]) cfg1_start_en <= 1'b0;

      // cfg_addr[2] selects the channel, cfg_addr[1:0] selects the register.
      if (cfg_we) begin
        case (channel_sel)
          1'b0: begin
            case (reg_sel)
              REG_SRC:  cfg0_src_base <= cfg_wdata[ADDR_W-1:0];
              REG_DST:  cfg0_dst_base <= cfg_wdata[ADDR_W-1:0];
              REG_LEN:  cfg0_len      <= cfg_wdata[LEN_W-1:0];
              REG_CTRL: begin
                cfg0_start_en <= cfg_wdata[CTRL_START_BIT];
                cfg0_inc_src  <= cfg_wdata[CTRL_INC_SRC_BIT];
                cfg0_inc_dst  <= cfg_wdata[CTRL_INC_DST_BIT];
              end
              default: begin end
            endcase
          end
          1'b1: begin
            case (reg_sel)
              REG_SRC:  cfg1_src_base <= cfg_wdata[ADDR_W-1:0];
              REG_DST:  cfg1_dst_base <= cfg_wdata[ADDR_W-1:0];
              REG_LEN:  cfg1_len      <= cfg_wdata[LEN_W-1:0];
              REG_CTRL: begin
                cfg1_start_en <= cfg_wdata[CTRL_START_BIT];
                cfg1_inc_src  <= cfg_wdata[CTRL_INC_SRC_BIT];
                cfg1_inc_dst  <= cfg_wdata[CTRL_INC_DST_BIT];
              end
              default: begin end
            endcase
          end
        endcase
      end
    end
  end

  always_comb begin
    cfg_rdata = 32'h0000_0000;

    if (cfg_re) begin
      // Status bits share the control register so software can poll progress
      // without needing a separate status address.
      case (channel_sel)
        1'b0: begin
          case (reg_sel)
            REG_SRC:  cfg_rdata[ADDR_W-1:0] = cfg0_src_base;
            REG_DST:  cfg_rdata[ADDR_W-1:0] = cfg0_dst_base;
            REG_LEN:  cfg_rdata[LEN_W-1:0]  = cfg0_len;
            REG_CTRL: begin
              cfg_rdata[CTRL_START_BIT]   = cfg0_start_en;
              cfg_rdata[CTRL_INC_SRC_BIT] = cfg0_inc_src;
              cfg_rdata[CTRL_INC_DST_BIT] = cfg0_inc_dst;
              cfg_rdata[8]                = chan_active[0];
              cfg_rdata[9]                = chan_done[0];
            end
            default: begin end
          endcase
        end
        1'b1: begin
          case (reg_sel)
            REG_SRC:  cfg_rdata[ADDR_W-1:0] = cfg1_src_base;
            REG_DST:  cfg_rdata[ADDR_W-1:0] = cfg1_dst_base;
            REG_LEN:  cfg_rdata[LEN_W-1:0]  = cfg1_len;
            REG_CTRL: begin
              cfg_rdata[CTRL_START_BIT]   = cfg1_start_en;
              cfg_rdata[CTRL_INC_SRC_BIT] = cfg1_inc_src;
              cfg_rdata[CTRL_INC_DST_BIT] = cfg1_inc_dst;
              cfg_rdata[8]                = chan_active[1];
              cfg_rdata[9]                = chan_done[1];
            end
            default: begin end
          endcase
        end
      endcase
    end
  end

endmodule
