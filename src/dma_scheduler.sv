import dma_pkg::*;

module dma_scheduler (
  // Clock and active-low reset.
  input  logic                    clk,
  input  logic                    rst_n,

  // Controller handshake: advance after the selected channel is accepted.
  input  logic                    grant_advance,
  output logic                    grant_valid,
  output logic [$clog2(N_CH)-1:0] grant_idx,

  // Start latches from cfg_reg.
  input  logic                    cfg0_start_en,
  input  logic                    cfg1_start_en,

  // Active flags from dma_controller.
  input  logic                    ch0_active,
  input  logic                    ch1_active
);

  logic last_grant, last_grant_next;
  logic ch0_ready;
  logic ch1_ready;

  // A channel is schedulable only when software requested it and it is idle.
  assign ch0_ready = cfg0_start_en && !ch0_active;
  assign ch1_ready = cfg1_start_en && !ch1_active;

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) last_grant <= 1'b1;
    else        last_grant <= last_grant_next;
  end

  always_comb begin
    grant_valid = 1'b0;
    grant_idx   = '0;

    // Round-robin priority alternates after a grant is consumed. With two
    // channels, last_grant is enough to remember who should be deprioritized.
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
