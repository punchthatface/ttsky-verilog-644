import dma_pkg::*;

module dma_controller (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  sched_valid,
  input  logic [$clog2(N_CH)-1:0] sched_idx,
  output logic                  sched_advance,
  input  dma_cfg_t              cfg0_in,
  input  dma_cfg_t              cfg1_in,
  output logic [N_CH-1:0]       start_clear,
  output dma_chan_state_t       chan0_state_out,
  output dma_chan_state_t       chan1_state_out,
  output mem_req_t              mem_req,
  input  mem_rsp_t              mem_rsp
);

  dma_state_t state, state_next;
  dma_chan_state_t chan0_state, chan0_state_next;
  dma_chan_state_t chan1_state, chan1_state_next;

  logic            active_ch, active_ch_next;
  logic [DATA_W-1:0] read_data_reg, read_data_reg_next;
  logic            write_busy_seen, write_busy_seen_next;

  logic [ADDR_W-1:0] selected_src_base;
  logic [ADDR_W-1:0] selected_dst_base;
  logic [LEN_W-1:0]  selected_len;
  logic              selected_inc_src;
  logic              selected_inc_dst;

  logic [ADDR_W-1:0] selected_src_cur;
  logic [ADDR_W-1:0] selected_dst_cur;
  logic [LEN_W-1:0]  selected_len_rem;
  logic              selected_state_inc_src;
  logic              selected_state_inc_dst;

  assign selected_src_base      = active_ch ? cfg1_in.src_base      : cfg0_in.src_base;
  assign selected_dst_base      = active_ch ? cfg1_in.dst_base      : cfg0_in.dst_base;
  assign selected_len           = active_ch ? cfg1_in.len           : cfg0_in.len;
  assign selected_inc_src       = active_ch ? cfg1_in.inc_src       : cfg0_in.inc_src;
  assign selected_inc_dst       = active_ch ? cfg1_in.inc_dst       : cfg0_in.inc_dst;

  assign selected_src_cur       = active_ch ? chan1_state.src_cur   : chan0_state.src_cur;
  assign selected_dst_cur       = active_ch ? chan1_state.dst_cur   : chan0_state.dst_cur;
  assign selected_len_rem       = active_ch ? chan1_state.len_rem   : chan0_state.len_rem;
  assign selected_state_inc_src = active_ch ? chan1_state.inc_src   : chan0_state.inc_src;
  assign selected_state_inc_dst = active_ch ? chan1_state.inc_dst   : chan0_state.inc_dst;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state         <= DMA_IDLE;
      active_ch     <= 1'b0;
      read_data_reg <= '0;
      write_busy_seen <= 1'b0;
      chan0_state   <= '0;
      chan1_state   <= '0;
    end else begin
      state         <= state_next;
      active_ch     <= active_ch_next;
      read_data_reg <= read_data_reg_next;
      write_busy_seen <= write_busy_seen_next;
      chan0_state   <= chan0_state_next;
      chan1_state   <= chan1_state_next;
    end
  end

  always_comb begin
    state_next         = state;
    active_ch_next     = active_ch;
    read_data_reg_next = read_data_reg;
    write_busy_seen_next = write_busy_seen;
    sched_advance      = 1'b0;
    start_clear        = '0;
    mem_req            = '0;

    chan0_state_next   = chan0_state;
    chan1_state_next   = chan1_state;

    case (state)
      DMA_IDLE: begin
        if (sched_valid) begin
          active_ch_next = sched_idx[0];
          state_next     = DMA_SELECT_CH;
        end
      end

      DMA_SELECT_CH: begin
        sched_advance = 1'b1;
        start_clear[active_ch] = 1'b1;

        if (!active_ch) begin
          chan0_state_next.src_cur = cfg0_in.src_base;
          chan0_state_next.dst_cur = cfg0_in.dst_base;
          chan0_state_next.len_rem = cfg0_in.len;
          chan0_state_next.inc_src = cfg0_in.inc_src;
          chan0_state_next.inc_dst = cfg0_in.inc_dst;
          chan0_state_next.active  = (cfg0_in.len != '0);
          chan0_state_next.done    = (cfg0_in.len == '0);
        end else begin
          chan1_state_next.src_cur = cfg1_in.src_base;
          chan1_state_next.dst_cur = cfg1_in.dst_base;
          chan1_state_next.len_rem = cfg1_in.len;
          chan1_state_next.inc_src = cfg1_in.inc_src;
          chan1_state_next.inc_dst = cfg1_in.inc_dst;
          chan1_state_next.active  = (cfg1_in.len != '0);
          chan1_state_next.done    = (cfg1_in.len == '0);
        end

        state_next = DMA_LOAD_STATE;
      end

      DMA_LOAD_STATE: begin
        if (selected_len_rem == '0) begin
          if (!active_ch) begin
            chan0_state_next.active = 1'b0;
            chan0_state_next.done   = 1'b1;
          end else begin
            chan1_state_next.active = 1'b0;
            chan1_state_next.done   = 1'b1;
          end
          state_next = DMA_COMPLETE;
        end else begin
          state_next = DMA_ISSUE_READ;
        end
      end

      DMA_ISSUE_READ: begin
        mem_req.valid = 1'b1;
        mem_req.rw    = 1'b0;
        mem_req.addr  = selected_src_cur;
        mem_req.wdata = '0;

        if (mem_rsp.ready) begin
          state_next = DMA_WAIT_READ;
        end
      end

      DMA_WAIT_READ: begin
        if (mem_rsp.valid) begin
          read_data_reg_next = mem_rsp.rdata;
          state_next         = DMA_ISSUE_WRITE;
        end
      end

      DMA_ISSUE_WRITE: begin
        mem_req.valid = 1'b1;
        mem_req.rw    = 1'b1;
        mem_req.addr  = selected_dst_cur;
        mem_req.wdata = read_data_reg;

        if (mem_rsp.ready) begin
          write_busy_seen_next = 1'b0;
          state_next = DMA_WAIT_WRITE;
        end
      end

      DMA_WAIT_WRITE: begin
        if (!write_busy_seen) begin
          if (!mem_rsp.ready) begin
            write_busy_seen_next = 1'b1;
          end
        end else if (mem_rsp.ready) begin
          state_next = DMA_UPDATE_STATE;
        end
      end

      DMA_UPDATE_STATE: begin
        if (!active_ch) begin
          chan0_state_next.len_rem = chan0_state.len_rem - 1'b1;
          if (selected_state_inc_src) chan0_state_next.src_cur = chan0_state.src_cur + 1'b1;
          if (selected_state_inc_dst) chan0_state_next.dst_cur = chan0_state.dst_cur + 1'b1;

          if (chan0_state.len_rem == 16'd1) begin
            chan0_state_next.active = 1'b0;
            chan0_state_next.done   = 1'b1;
            state_next = DMA_COMPLETE;
          end else begin
            state_next = DMA_ISSUE_READ;
          end
        end else begin
          chan1_state_next.len_rem = chan1_state.len_rem - 1'b1;
          if (selected_state_inc_src) chan1_state_next.src_cur = chan1_state.src_cur + 1'b1;
          if (selected_state_inc_dst) chan1_state_next.dst_cur = chan1_state.dst_cur + 1'b1;

          if (chan1_state.len_rem == 16'd1) begin
            chan1_state_next.active = 1'b0;
            chan1_state_next.done   = 1'b1;
            state_next = DMA_COMPLETE;
          end else begin
            state_next = DMA_ISSUE_READ;
          end
        end
      end

      DMA_COMPLETE: begin
        write_busy_seen_next = 1'b0;
        state_next = DMA_IDLE;
      end

      default: begin
        write_busy_seen_next = 1'b0;
        state_next = DMA_IDLE;
      end
    endcase
  end

  assign chan0_state_out = chan0_state;
  assign chan1_state_out = chan1_state;

endmodule
