module spi_psram_ctrl
import dma_pkg::*;
#(
  parameter int RESET_CYCLES          = 20000,
  parameter int RESET_RECOVERY_CYCLES = 8
)(
  input  logic              clk,
  input  logic              rst_n,

  // Request interface from DMA / top-level logic
  input  logic              req_valid,
  input  logic              req_rw,       // 0 = read, 1 = write
  input  logic [ADDR_W-1:0] req_addr,
  input  logic [DATA_W-1:0] req_wdata,
  output logic              req_ready,

  // Response interface back to DMA / top-level logic
  output logic              rsp_valid,
  output logic [DATA_W-1:0] rsp_rdata,
  output logic              busy,

  // External SPI pins to PSRAM
  output logic              spi_clk,
  output logic              spi_cs_n,
  output logic              spi_mosi,
  input  logic              spi_miso
);

  localparam logic [7:0] SPI_CMD_RESET_ENABLE = 8'h66;
  localparam logic [7:0] SPI_CMD_RESET         = 8'h99;
  localparam int SPI_FRAME_W = 40;

  typedef enum logic [3:0] {
    ST_POWER_UP_WAIT,
    ST_SEND_RESET_ENABLE,
    ST_WAIT_RESET_ENABLE,
    ST_SEND_RESET,
    ST_WAIT_RESET,
    ST_RESET_RECOVERY,
    ST_IDLE,
    ST_SEND_ACCESS,
    ST_WAIT_ACCESS
  } state_t;

  state_t state, state_next;

  logic [15:0] delay_count, delay_count_next;

  logic [ADDR_W-1:0] request_addr_reg,  request_addr_reg_next;
  logic [DATA_W-1:0] request_wdata_reg, request_wdata_reg_next;
  logic              request_rw_reg,    request_rw_reg_next;

  logic                 spi_start;
  logic [5:0]           spi_nbits;
  logic [SPI_FRAME_W-1:0] spi_tx_data;
  logic                 spi_rx_en;
  logic                 spi_done;
  logic                 spi_busy;
  logic [SPI_FRAME_W-1:0] spi_rx_data;

  logic              req_ready_next;
  logic              rsp_valid_next;
  logic [DATA_W-1:0] rsp_rdata_next;
  logic              busy_next;

  spi_master #(
    .MAX_BITS(SPI_FRAME_W)
  ) u_spi_master (
    .clk      (clk),
    .rst_n    (rst_n),
    .start    (spi_start),
    .nbits    (spi_nbits),
    .tx_data  (spi_tx_data),
    .rx_en    (spi_rx_en),
    .busy     (spi_busy),
    .done     (spi_done),
    .rx_data  (spi_rx_data),
    .spi_cs_n (spi_cs_n),
    .spi_sck  (spi_clk),
    .spi_mosi (spi_mosi),
    .spi_miso (spi_miso)
  );

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      state             <= ST_POWER_UP_WAIT;
      delay_count       <= '0;
      request_addr_reg  <= '0;
      request_wdata_reg <= '0;
      request_rw_reg    <= 1'b0;
      req_ready         <= 1'b0;
      rsp_valid         <= 1'b0;
      rsp_rdata         <= '0;
      busy              <= 1'b1;
    end else begin
      state             <= state_next;
      delay_count       <= delay_count_next;
      request_addr_reg  <= request_addr_reg_next;
      request_wdata_reg <= request_wdata_reg_next;
      request_rw_reg    <= request_rw_reg_next;
      req_ready         <= req_ready_next;
      rsp_valid         <= rsp_valid_next;
      rsp_rdata         <= rsp_rdata_next;
      busy              <= busy_next;
    end
  end

  always_comb begin
    state_next             = state;
    delay_count_next       = delay_count;
    request_addr_reg_next  = request_addr_reg;
    request_wdata_reg_next = request_wdata_reg;
    request_rw_reg_next    = request_rw_reg;

    req_ready_next         = 1'b0;
    rsp_valid_next         = 1'b0;
    rsp_rdata_next         = rsp_rdata;
    busy_next              = 1'b1;

    spi_start              = 1'b0;
    spi_nbits              = 6'd0;
    spi_tx_data            = '0;
    spi_rx_en              = 1'b0;

    case (state)
      ST_POWER_UP_WAIT: begin
        if (delay_count == RESET_CYCLES - 1) begin
          delay_count_next = '0;
          state_next       = ST_SEND_RESET_ENABLE;
        end else begin
          delay_count_next = delay_count + 1'b1;
        end
      end

      ST_SEND_RESET_ENABLE: begin
        if (!spi_busy) begin
          spi_start   = 1'b1;
          spi_nbits   = 6'd8;
          spi_tx_data = {{(SPI_FRAME_W-8){1'b0}}, SPI_CMD_RESET_ENABLE};
          state_next  = ST_WAIT_RESET_ENABLE;
        end
      end

      ST_WAIT_RESET_ENABLE: begin
        if (spi_done) begin
          state_next = ST_SEND_RESET;
        end
      end

      ST_SEND_RESET: begin
        if (!spi_busy) begin
          spi_start   = 1'b1;
          spi_nbits   = 6'd8;
          spi_tx_data = {{(SPI_FRAME_W-8){1'b0}}, SPI_CMD_RESET};
          state_next  = ST_WAIT_RESET;
        end
      end

      ST_WAIT_RESET: begin
        if (spi_done) begin
          delay_count_next = '0;
          state_next       = ST_RESET_RECOVERY;
        end
      end

      ST_RESET_RECOVERY: begin
        if (delay_count == RESET_RECOVERY_CYCLES - 1) begin
          delay_count_next = '0;
          state_next       = ST_IDLE;
        end else begin
          delay_count_next = delay_count + 1'b1;
        end
      end

      ST_IDLE: begin
        req_ready_next = 1'b1;
        busy_next      = 1'b0;

        if (req_valid) begin
          request_addr_reg_next  = req_addr;
          request_wdata_reg_next = req_wdata;
          request_rw_reg_next    = req_rw;
          state_next             = ST_SEND_ACCESS;
        end
      end

      ST_SEND_ACCESS: begin
        if (!spi_busy) begin
          spi_start = 1'b1;
          spi_nbits = 6'd40;

          if (request_rw_reg) begin
            spi_tx_data = {
              SPI_CMD_WRITE,
              1'b0,
              request_addr_reg[22:0],
              request_wdata_reg
            };
            spi_rx_en = 1'b0;
          end else begin
            spi_tx_data = {
              SPI_CMD_READ,
              1'b0,
              request_addr_reg[22:0],
              8'h00
            };
            spi_rx_en = 1'b1;
          end

          state_next = ST_WAIT_ACCESS;
        end
      end

      ST_WAIT_ACCESS: begin
        if (spi_done) begin
          if (!request_rw_reg) begin
            rsp_valid_next = 1'b1;
            rsp_rdata_next = spi_rx_data[7:0];
          end
          state_next = ST_IDLE;
        end
      end

      default: begin
        state_next = ST_POWER_UP_WAIT;
      end
    endcase
  end

endmodule
