import dma_pkg::*;

module tinydma_top #(
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

  dma_cfg_t        cfg0_reg, cfg1_reg;
  dma_chan_state_t chan0_state, chan1_state;
  mem_req_t        mem_req;
  mem_rsp_t        mem_rsp;

  logic [N_CH-1:0] start_clear;
  logic [N_CH-1:0] chan_active;
  logic [N_CH-1:0] chan_done;
  logic            sched_valid;
  logic [$clog2(N_CH)-1:0] sched_idx;
  logic            sched_advance;

  assign chan_active[0] = chan0_state.active;
  assign chan_active[1] = chan1_state.active;
  assign chan_done[0]   = chan0_state.done;
  assign chan_done[1]   = chan1_state.done;
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
    .cfg0_out    (cfg0_reg),
    .cfg1_out    (cfg1_reg)
  );

  dma_scheduler u_dma_scheduler (
    .clk          (clk),
    .rst_n        (rst_n),
    .grant_advance(sched_advance),
    .cfg0_in      (cfg0_reg),
    .cfg1_in      (cfg1_reg),
    .ch0_active   (chan0_state.active),
    .ch1_active   (chan1_state.active),
    .grant_valid  (sched_valid),
    .grant_idx    (sched_idx)
  );

  dma_controller u_dma_controller (
    .clk          (clk),
    .rst_n        (rst_n),
    .sched_valid  (sched_valid),
    .sched_idx    (sched_idx),
    .sched_advance(sched_advance),
    .cfg0_in      (cfg0_reg),
    .cfg1_in      (cfg1_reg),
    .start_clear  (start_clear),
    .chan0_state_out(chan0_state),
    .chan1_state_out(chan1_state),
    .mem_req      (mem_req),
    .mem_rsp      (mem_rsp)
  );

  spi_psram_ctrl #(
    .RESET_CYCLES(PSRAM_RESET_CYCLES),
    .RESET_RECOVERY_CYCLES(PSRAM_RESET_RECOVERY_CYCLES)
  ) u_spi_psram_ctrl (
    .clk      (clk),
    .rst_n    (rst_n),
    .req_valid(mem_req.valid),
    .req_rw   (mem_req.rw),
    .req_addr (mem_req.addr),
    .req_wdata(mem_req.wdata),
    .req_ready(mem_rsp.ready),
    .rsp_valid(mem_rsp.valid),
    .rsp_rdata(mem_rsp.rdata),
    .busy     (dma_busy),
    .spi_clk  (spi_clk),
    .spi_cs_n (spi_cs_n),
    .spi_mosi (spi_mosi),
    .spi_miso (spi_miso)
  );

endmodule
