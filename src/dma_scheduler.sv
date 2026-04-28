module dma_scheduler
import dma_pkg::*;
(
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  grant_advance,
  input  logic                  cfg0_start_en,
  input  logic                  cfg1_start_en,
  input  logic                  ch0_active,
  input  logic                  ch1_active,
  output logic                  grant_valid,
  output logic [$clog2(N_CH)-1:0] grant_idx
);

  logic last_grant, last_grant_next;
  logic ch0_ready;
  logic ch1_ready;

  assign ch0_ready = cfg0_start_en && !ch0_active;
  assign ch1_ready = cfg1_start_en && !ch1_active;

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) last_grant <= 1'b1;
    else        last_grant <= last_grant_next;
  end

  always_comb begin
    grant_valid = 1'b0;
    grant_idx   = '0;

    if (!last_grant) begin
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
    if (grant_advance && grant_valid) last_grant_next = grant_idx[0];
  end

endmodule
