module tinydma_top
import dma_pkg::*;
#(
  parameter int PSRAM_RESET_CYCLES          = 20000,
  parameter int PSRAM_RESET_RECOVERY_CYCLES = 8
) (
  input  logic                              clk,
  input  logic                              rst_n,
  input  logic                              cfg_we,
  input  logic                              cfg_re,
  input  logic [$clog2(N_CH*4)-1:0]         cfg_addr,
  input  logic [31:0]                       cfg_wdata,
  output logic [31:0]                       cfg_rdata,
  output logic                              dma_busy,
  output logic [N_CH-1:0]                   chan_active_o,
  output logic [N_CH-1:0]                   chan_done_o,
  output logic                              spi_clk,
  output logic                              spi_cs_n,
  output logic                              spi_mosi,
  input  logic                              spi_miso
);

  logic [N_CH-1:0] start_clear;
  logic [N_CH-1:0] chan_active;
  logic [N_CH-1:0] chan_done;
  logic            sched_valid;
  logic [$clog2(N_CH)-1:0] sched_idx;
  logic            sched_advance;

  logic [ADDR_W-1:0] cfg0_src_base, cfg0_dst_base;
  logic [LEN_W-1:0]  cfg0_len;
  logic              cfg0_inc_src, cfg0_inc_dst, cfg0_start_en;
  logic [ADDR_W-1:0] cfg1_src_base, cfg1_dst_base;
  logic [LEN_W-1:0]  cfg1_len;
  logic              cfg1_inc_src, cfg1_inc_dst, cfg1_start_en;

  logic [ADDR_W-1:0] chan0_src_cur, chan0_dst_cur;
  logic [LEN_W-1:0]  chan0_len_rem;
  logic              chan0_inc_src, chan0_inc_dst, chan0_active, chan0_done;
  logic [ADDR_W-1:0] chan1_src_cur, chan1_dst_cur;
  logic [LEN_W-1:0]  chan1_len_rem;
  logic              chan1_inc_src, chan1_inc_dst, chan1_active, chan1_done;

  logic              mem_req_valid, mem_req_rw;
  logic [ADDR_W-1:0] mem_req_addr;
  logic [DATA_W-1:0] mem_req_wdata;
  logic              mem_rsp_ready, mem_rsp_valid;
  logic [DATA_W-1:0] mem_rsp_rdata;

  assign chan_active[0] = chan0_active;
  assign chan_active[1] = chan1_active;
  assign chan_done[0]   = chan0_done;
  assign chan_done[1]   = chan1_done;
  assign chan_active_o  = chan_active;
  assign chan_done_o    = chan_done;

  cfg_reg u_cfg_reg (
    .clk         (clk),
    .rst_n       (rst_n),
    .cfg_we      (cfg_we),
    .cfg_re      (cfg_re),
    .cfg_addr    (cfg_addr),
    .cfg_wdata   (cfg_wdata),
    .cfg_rdata   (cfg_rdata),
    .start_clear (start_clear),
    .chan_active (chan_active),
    .chan_done   (chan_done),
    .cfg0_src_base(cfg0_src_base),
    .cfg0_dst_base(cfg0_dst_base),
    .cfg0_len    (cfg0_len),
    .cfg0_inc_src(cfg0_inc_src),
    .cfg0_inc_dst(cfg0_inc_dst),
    .cfg0_start_en(cfg0_start_en),
    .cfg1_src_base(cfg1_src_base),
    .cfg1_dst_base(cfg1_dst_base),
    .cfg1_len    (cfg1_len),
    .cfg1_inc_src(cfg1_inc_src),
    .cfg1_inc_dst(cfg1_inc_dst),
    .cfg1_start_en(cfg1_start_en)
  );

  dma_scheduler u_dma_scheduler (
    .clk          (clk),
    .rst_n        (rst_n),
    .grant_advance(sched_advance),
    .cfg0_start_en(cfg0_start_en),
    .cfg1_start_en(cfg1_start_en),
    .ch0_active   (chan0_active),
    .ch1_active   (chan1_active),
    .grant_valid  (sched_valid),
    .grant_idx    (sched_idx)
  );

  dma_controller u_dma_controller (
    .clk          (clk),
    .rst_n        (rst_n),
    .sched_valid  (sched_valid),
    .sched_idx    (sched_idx),
    .sched_advance(sched_advance),
    .cfg0_src_base(cfg0_src_base),
    .cfg0_dst_base(cfg0_dst_base),
    .cfg0_len    (cfg0_len),
    .cfg0_inc_src(cfg0_inc_src),
    .cfg0_inc_dst(cfg0_inc_dst),
    .cfg1_src_base(cfg1_src_base),
    .cfg1_dst_base(cfg1_dst_base),
    .cfg1_len    (cfg1_len),
    .cfg1_inc_src(cfg1_inc_src),
    .cfg1_inc_dst(cfg1_inc_dst),
    .start_clear  (start_clear),
    .chan0_src_cur(chan0_src_cur),
    .chan0_dst_cur(chan0_dst_cur),
    .chan0_len_rem(chan0_len_rem),
    .chan0_inc_src(chan0_inc_src),
    .chan0_inc_dst(chan0_inc_dst),
    .chan0_active (chan0_active),
    .chan0_done   (chan0_done),
    .chan1_src_cur(chan1_src_cur),
    .chan1_dst_cur(chan1_dst_cur),
    .chan1_len_rem(chan1_len_rem),
    .chan1_inc_src(chan1_inc_src),
    .chan1_inc_dst(chan1_inc_dst),
    .chan1_active (chan1_active),
    .chan1_done   (chan1_done),
    .mem_req_valid(mem_req_valid),
    .mem_req_rw   (mem_req_rw),
    .mem_req_addr (mem_req_addr),
    .mem_req_wdata(mem_req_wdata),
    .mem_rsp_ready(mem_rsp_ready),
    .mem_rsp_valid(mem_rsp_valid),
    .mem_rsp_rdata(mem_rsp_rdata)
  );

  spi_psram_ctrl #(
    .RESET_CYCLES(PSRAM_RESET_CYCLES),
    .RESET_RECOVERY_CYCLES(PSRAM_RESET_RECOVERY_CYCLES)
  ) u_spi_psram_ctrl (
    .clk      (clk),
    .rst_n    (rst_n),
    .req_valid(mem_req_valid),
    .req_rw   (mem_req_rw),
    .req_addr (mem_req_addr),
    .req_wdata(mem_req_wdata),
    .req_ready(mem_rsp_ready),
    .rsp_valid(mem_rsp_valid),
    .rsp_rdata(mem_rsp_rdata),
    .busy     (dma_busy),
    .spi_clk  (spi_clk),
    .spi_cs_n (spi_cs_n),
    .spi_mosi (spi_mosi),
    .spi_miso (spi_miso)
  );

endmodule
