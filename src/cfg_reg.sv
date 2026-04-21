import dma_pkg::*;

module cfg_reg #(
  parameter int N_REGS_PER_CH = 4
) (
  input  logic                                  clk,
  input  logic                                  rst_n,
  input  logic                                  cfg_we,
  input  logic                                  cfg_re,
  input  logic [$clog2(N_CH*N_REGS_PER_CH)-1:0] cfg_addr,
  input  logic [31:0]                           cfg_wdata,
  output logic [31:0]                           cfg_rdata,
  input  logic [N_CH-1:0]                       start_clear,
  input  logic [N_CH-1:0]                       chan_active,
  input  logic [N_CH-1:0]                       chan_done,
  output dma_cfg_t                              cfg0_out,
  output dma_cfg_t                              cfg1_out
);

  localparam int REG_SRC  = 0;
  localparam int REG_DST  = 1;
  localparam int REG_LEN  = 2;
  localparam int REG_CTRL = 3;

  dma_cfg_t cfg0_reg, cfg1_reg;

  logic channel_sel;
  logic [1:0] reg_sel;

  assign channel_sel = cfg_addr[2];
  assign reg_sel     = cfg_addr[1:0];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cfg0_reg <= '0;
      cfg1_reg <= '0;
    end else begin
      if (start_clear[0]) begin
        cfg0_reg.start_en <= 1'b0;
      end
      if (start_clear[1]) begin
        cfg1_reg.start_en <= 1'b0;
      end

      if (cfg_we) begin
        unique case (channel_sel)
          1'b0: begin
            unique case (reg_sel)
              REG_SRC:  cfg0_reg.src_base <= cfg_wdata[ADDR_W-1:0];
              REG_DST:  cfg0_reg.dst_base <= cfg_wdata[ADDR_W-1:0];
              REG_LEN:  cfg0_reg.len      <= cfg_wdata[LEN_W-1:0];
              REG_CTRL: begin
                cfg0_reg.start_en <= cfg_wdata[CTRL_START_BIT];
                cfg0_reg.inc_src  <= cfg_wdata[CTRL_INC_SRC_BIT];
                cfg0_reg.inc_dst  <= cfg_wdata[CTRL_INC_DST_BIT];
              end
              default: begin
              end
            endcase
          end
          1'b1: begin
            unique case (reg_sel)
              REG_SRC:  cfg1_reg.src_base <= cfg_wdata[ADDR_W-1:0];
              REG_DST:  cfg1_reg.dst_base <= cfg_wdata[ADDR_W-1:0];
              REG_LEN:  cfg1_reg.len      <= cfg_wdata[LEN_W-1:0];
              REG_CTRL: begin
                cfg1_reg.start_en <= cfg_wdata[CTRL_START_BIT];
                cfg1_reg.inc_src  <= cfg_wdata[CTRL_INC_SRC_BIT];
                cfg1_reg.inc_dst  <= cfg_wdata[CTRL_INC_DST_BIT];
              end
              default: begin
              end
            endcase
          end
        endcase
      end
    end
  end

  always_comb begin
    cfg_rdata = 32'h0000_0000;

    if (cfg_re) begin
      unique case (channel_sel)
        1'b0: begin
          unique case (reg_sel)
            REG_SRC:  cfg_rdata[ADDR_W-1:0] = cfg0_reg.src_base;
            REG_DST:  cfg_rdata[ADDR_W-1:0] = cfg0_reg.dst_base;
            REG_LEN:  cfg_rdata[LEN_W-1:0]  = cfg0_reg.len;
            REG_CTRL: begin
              cfg_rdata[CTRL_START_BIT]   = cfg0_reg.start_en;
              cfg_rdata[CTRL_INC_SRC_BIT] = cfg0_reg.inc_src;
              cfg_rdata[CTRL_INC_DST_BIT] = cfg0_reg.inc_dst;
              cfg_rdata[8]                = chan_active[0];
              cfg_rdata[9]                = chan_done[0];
            end
            default: begin
            end
          endcase
        end
        1'b1: begin
          unique case (reg_sel)
            REG_SRC:  cfg_rdata[ADDR_W-1:0] = cfg1_reg.src_base;
            REG_DST:  cfg_rdata[ADDR_W-1:0] = cfg1_reg.dst_base;
            REG_LEN:  cfg_rdata[LEN_W-1:0]  = cfg1_reg.len;
            REG_CTRL: begin
              cfg_rdata[CTRL_START_BIT]   = cfg1_reg.start_en;
              cfg_rdata[CTRL_INC_SRC_BIT] = cfg1_reg.inc_src;
              cfg_rdata[CTRL_INC_DST_BIT] = cfg1_reg.inc_dst;
              cfg_rdata[8]                = chan_active[1];
              cfg_rdata[9]                = chan_done[1];
            end
            default: begin
            end
          endcase
        end
      endcase
    end
  end

  assign cfg0_out = cfg0_reg;
  assign cfg1_out = cfg1_reg;

endmodule
