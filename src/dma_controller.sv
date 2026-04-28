module dma_controller
import dma_pkg::*;
(
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  sched_valid,
  input  logic [$clog2(N_CH)-1:0] sched_idx,
  output logic                  sched_advance,
  input  logic [ADDR_W-1:0]     cfg0_src_base,
  input  logic [ADDR_W-1:0]     cfg0_dst_base,
  input  logic [LEN_W-1:0]      cfg0_len,
  input  logic                  cfg0_inc_src,
  input  logic                  cfg0_inc_dst,
  input  logic [ADDR_W-1:0]     cfg1_src_base,
  input  logic [ADDR_W-1:0]     cfg1_dst_base,
  input  logic [LEN_W-1:0]      cfg1_len,
  input  logic                  cfg1_inc_src,
  input  logic                  cfg1_inc_dst,
  output logic [N_CH-1:0]       start_clear,
  output logic [ADDR_W-1:0]     chan0_src_cur,
  output logic [ADDR_W-1:0]     chan0_dst_cur,
  output logic [LEN_W-1:0]      chan0_len_rem,
  output logic                  chan0_inc_src,
  output logic                  chan0_inc_dst,
  output logic                  chan0_active,
  output logic                  chan0_done,
  output logic [ADDR_W-1:0]     chan1_src_cur,
  output logic [ADDR_W-1:0]     chan1_dst_cur,
  output logic [LEN_W-1:0]      chan1_len_rem,
  output logic                  chan1_inc_src,
  output logic                  chan1_inc_dst,
  output logic                  chan1_active,
  output logic                  chan1_done,
  output logic                  mem_req_valid,
  output logic                  mem_req_rw,
  output logic [ADDR_W-1:0]     mem_req_addr,
  output logic [DATA_W-1:0]     mem_req_wdata,
  input  logic                  mem_rsp_ready,
  input  logic                  mem_rsp_valid,
  input  logic [DATA_W-1:0]     mem_rsp_rdata
);

  logic [3:0] state, state_next;

  logic active_ch, active_ch_next;
  logic [DATA_W-1:0] read_data_reg, read_data_reg_next;
  logic write_busy_seen, write_busy_seen_next;

  logic [ADDR_W-1:0] chan0_src_cur_next, chan0_dst_cur_next;
  logic [LEN_W-1:0]  chan0_len_rem_next;
  logic              chan0_inc_src_next, chan0_inc_dst_next, chan0_active_next, chan0_done_next;

  logic [ADDR_W-1:0] chan1_src_cur_next, chan1_dst_cur_next;
  logic [LEN_W-1:0]  chan1_len_rem_next;
  logic              chan1_inc_src_next, chan1_inc_dst_next, chan1_active_next, chan1_done_next;

  logic [ADDR_W-1:0] selected_src_cur;
  logic [ADDR_W-1:0] selected_dst_cur;
  logic [LEN_W-1:0]  selected_len_rem;
  logic              selected_state_inc_src;
  logic              selected_state_inc_dst;

  assign selected_src_cur       = active_ch ? chan1_src_cur : chan0_src_cur;
  assign selected_dst_cur       = active_ch ? chan1_dst_cur : chan0_dst_cur;
  assign selected_len_rem       = active_ch ? chan1_len_rem : chan0_len_rem;
  assign selected_state_inc_src = active_ch ? chan1_inc_src : chan0_inc_src;
  assign selected_state_inc_dst = active_ch ? chan1_inc_dst : chan0_inc_dst;

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      state           <= DMA_IDLE;
      active_ch       <= 1'b0;
      read_data_reg   <= '0;
      write_busy_seen <= 1'b0;
      chan0_src_cur   <= '0;
      chan0_dst_cur   <= '0;
      chan0_len_rem   <= '0;
      chan0_inc_src   <= 1'b0;
      chan0_inc_dst   <= 1'b0;
      chan0_active    <= 1'b0;
      chan0_done      <= 1'b0;
      chan1_src_cur   <= '0;
      chan1_dst_cur   <= '0;
      chan1_len_rem   <= '0;
      chan1_inc_src   <= 1'b0;
      chan1_inc_dst   <= 1'b0;
      chan1_active    <= 1'b0;
      chan1_done      <= 1'b0;
    end else begin
      state           <= state_next;
      active_ch       <= active_ch_next;
      read_data_reg   <= read_data_reg_next;
      write_busy_seen <= write_busy_seen_next;
      chan0_src_cur   <= chan0_src_cur_next;
      chan0_dst_cur   <= chan0_dst_cur_next;
      chan0_len_rem   <= chan0_len_rem_next;
      chan0_inc_src   <= chan0_inc_src_next;
      chan0_inc_dst   <= chan0_inc_dst_next;
      chan0_active    <= chan0_active_next;
      chan0_done      <= chan0_done_next;
      chan1_src_cur   <= chan1_src_cur_next;
      chan1_dst_cur   <= chan1_dst_cur_next;
      chan1_len_rem   <= chan1_len_rem_next;
      chan1_inc_src   <= chan1_inc_src_next;
      chan1_inc_dst   <= chan1_inc_dst_next;
      chan1_active    <= chan1_active_next;
      chan1_done      <= chan1_done_next;
    end
  end

  always_comb begin
    state_next           = state;
    active_ch_next       = active_ch;
    read_data_reg_next   = read_data_reg;
    write_busy_seen_next = write_busy_seen;
    sched_advance        = 1'b0;
    start_clear          = '0;

    mem_req_valid        = 1'b0;
    mem_req_rw           = 1'b0;
    mem_req_addr         = '0;
    mem_req_wdata        = '0;

    chan0_src_cur_next   = chan0_src_cur;
    chan0_dst_cur_next   = chan0_dst_cur;
    chan0_len_rem_next   = chan0_len_rem;
    chan0_inc_src_next   = chan0_inc_src;
    chan0_inc_dst_next   = chan0_inc_dst;
    chan0_active_next    = chan0_active;
    chan0_done_next      = chan0_done;

    chan1_src_cur_next   = chan1_src_cur;
    chan1_dst_cur_next   = chan1_dst_cur;
    chan1_len_rem_next   = chan1_len_rem;
    chan1_inc_src_next   = chan1_inc_src;
    chan1_inc_dst_next   = chan1_inc_dst;
    chan1_active_next    = chan1_active;
    chan1_done_next      = chan1_done;

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
          chan0_src_cur_next = cfg0_src_base;
          chan0_dst_cur_next = cfg0_dst_base;
          chan0_len_rem_next = cfg0_len;
          chan0_inc_src_next = cfg0_inc_src;
          chan0_inc_dst_next = cfg0_inc_dst;
          chan0_active_next  = (cfg0_len != '0);
          chan0_done_next    = (cfg0_len == '0);
        end else begin
          chan1_src_cur_next = cfg1_src_base;
          chan1_dst_cur_next = cfg1_dst_base;
          chan1_len_rem_next = cfg1_len;
          chan1_inc_src_next = cfg1_inc_src;
          chan1_inc_dst_next = cfg1_inc_dst;
          chan1_active_next  = (cfg1_len != '0);
          chan1_done_next    = (cfg1_len == '0);
        end

        state_next = DMA_LOAD_STATE;
      end

      DMA_LOAD_STATE: begin
        if (selected_len_rem == '0) begin
          if (!active_ch) begin
            chan0_active_next = 1'b0;
            chan0_done_next   = 1'b1;
          end else begin
            chan1_active_next = 1'b0;
            chan1_done_next   = 1'b1;
          end
          state_next = DMA_COMPLETE;
        end else begin
          state_next = DMA_ISSUE_READ;
        end
      end

      DMA_ISSUE_READ: begin
        mem_req_valid = 1'b1;
        mem_req_rw    = 1'b0;
        mem_req_addr  = selected_src_cur;
        if (mem_rsp_ready) state_next = DMA_WAIT_READ;
      end

      DMA_WAIT_READ: begin
        if (mem_rsp_valid) begin
          read_data_reg_next = mem_rsp_rdata;
          state_next         = DMA_ISSUE_WRITE;
        end
      end

      DMA_ISSUE_WRITE: begin
        mem_req_valid = 1'b1;
        mem_req_rw    = 1'b1;
        mem_req_addr  = selected_dst_cur;
        mem_req_wdata = read_data_reg;
        if (mem_rsp_ready) begin
          write_busy_seen_next = 1'b0;
          state_next = DMA_WAIT_WRITE;
        end
      end

      DMA_WAIT_WRITE: begin
        if (!write_busy_seen) begin
          if (!mem_rsp_ready) write_busy_seen_next = 1'b1;
        end else if (mem_rsp_ready) begin
          state_next = DMA_UPDATE_STATE;
        end
      end

      DMA_UPDATE_STATE: begin
        if (!active_ch) begin
          chan0_len_rem_next = chan0_len_rem - 1'b1;
          if (selected_state_inc_src) chan0_src_cur_next = chan0_src_cur + 1'b1;
          if (selected_state_inc_dst) chan0_dst_cur_next = chan0_dst_cur + 1'b1;
          if (chan0_len_rem == 16'd1) begin
            chan0_active_next = 1'b0;
            chan0_done_next   = 1'b1;
            state_next = DMA_COMPLETE;
          end else begin
            state_next = DMA_ISSUE_READ;
          end
        end else begin
          chan1_len_rem_next = chan1_len_rem - 1'b1;
          if (selected_state_inc_src) chan1_src_cur_next = chan1_src_cur + 1'b1;
          if (selected_state_inc_dst) chan1_dst_cur_next = chan1_dst_cur + 1'b1;
          if (chan1_len_rem == 16'd1) begin
            chan1_active_next = 1'b0;
            chan1_done_next   = 1'b1;
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

endmodule
