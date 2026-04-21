import dma_pkg::*;

module dma_scheduler (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  grant_advance,
  input  dma_cfg_t              cfg0_in,
  input  dma_cfg_t              cfg1_in,
  input  logic                  ch0_active,
  input  logic                  ch1_active,
  output logic                  grant_valid,
  output logic [$clog2(N_CH)-1:0] grant_idx
);

  logic last_grant, last_grant_next;

  logic ch0_ready;
  logic ch1_ready;

  assign ch0_ready = cfg0_in.start_en && !ch0_active;
  assign ch1_ready = cfg1_in.start_en && !ch1_active;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      last_grant <= 1'b1;
    end else begin
      last_grant <= last_grant_next;
    end
  end

  always_comb begin
    grant_valid = 1'b0;
    grant_idx   = '0;

    if (last_grant == 1'b0) begin
      if (ch1_ready) begin
        grant_valid = 1'b1;
        grant_idx   = 1'b1;
      end else if (ch0_ready) begin
        grant_valid = 1'b1;
        grant_idx   = 1'b0;
      end
    end else begin
      if (ch0_ready) begin
        grant_valid = 1'b1;
        grant_idx   = 1'b0;
      end else if (ch1_ready) begin
        grant_valid = 1'b1;
        grant_idx   = 1'b1;
      end
    end
  end

  always_comb begin
    last_grant_next = last_grant;

    if (grant_advance && grant_valid) begin
      last_grant_next = grant_idx[0];
    end
  end

endmodule
