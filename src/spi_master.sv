module spi_master #(
  parameter int MAX_BITS = 40
)(
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  start,
  input  logic [5:0]            nbits,
  input  logic [MAX_BITS-1:0]   tx_data,
  input  logic                  rx_en,

  output logic                  busy,
  output logic                  done,
  output logic [MAX_BITS-1:0]   rx_data,

  output logic                  spi_cs_n,
  output logic                  spi_sck,
  output logic                  spi_mosi,
  input  logic                  spi_miso
);

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_BIT_SETUP,
    ST_BIT_HIGH,
    ST_BIT_LOW,
    ST_CS_HOLD,
    ST_DONE
  } state_t;

  state_t state, state_next;

  logic [MAX_BITS-1:0] tx_shift_reg, tx_shift_reg_next;
  logic [MAX_BITS-1:0] rx_shift_reg, rx_shift_reg_next;
  logic [5:0]          bits_left, bits_left_next;
  logic                rx_en_reg, rx_en_reg_next;

  logic spi_cs_n_reg, spi_cs_n_reg_next;
  logic spi_sck_reg,  spi_sck_reg_next;
  logic spi_mosi_reg, spi_mosi_reg_next;

  logic busy_next;
  logic done_next;
  logic [MAX_BITS-1:0] rx_data_next;

  assign spi_cs_n = spi_cs_n_reg;
  assign spi_sck  = spi_sck_reg;
  assign spi_mosi = spi_mosi_reg;

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
      state         <= ST_IDLE;
      tx_shift_reg  <= '0;
      rx_shift_reg  <= '0;
      bits_left     <= '0;
      rx_en_reg     <= 1'b0;
      spi_cs_n_reg  <= 1'b1;
      spi_sck_reg   <= 1'b0;
      spi_mosi_reg  <= 1'b0;
      busy          <= 1'b0;
      done          <= 1'b0;
      rx_data       <= '0;
    end else begin
      state         <= state_next;
      tx_shift_reg  <= tx_shift_reg_next;
      rx_shift_reg  <= rx_shift_reg_next;
      bits_left     <= bits_left_next;
      rx_en_reg     <= rx_en_reg_next;
      spi_cs_n_reg  <= spi_cs_n_reg_next;
      spi_sck_reg   <= spi_sck_reg_next;
      spi_mosi_reg  <= spi_mosi_reg_next;
      busy          <= busy_next;
      done          <= done_next;
      rx_data       <= rx_data_next;
    end
  end

  always_comb begin
    state_next        = state;
    tx_shift_reg_next = tx_shift_reg;
    rx_shift_reg_next = rx_shift_reg;
    bits_left_next    = bits_left;
    rx_en_reg_next    = rx_en_reg;

    spi_cs_n_reg_next = spi_cs_n_reg;
    spi_sck_reg_next  = spi_sck_reg;
    spi_mosi_reg_next = spi_mosi_reg;

    busy_next         = busy;
    done_next         = 1'b0;
    rx_data_next      = rx_data;

    case (state)
      ST_IDLE: begin
        spi_cs_n_reg_next = 1'b1;
        spi_sck_reg_next  = 1'b0;
        spi_mosi_reg_next = 1'b0;
        busy_next         = 1'b0;

        if (start) begin
          tx_shift_reg_next = tx_data << (MAX_BITS - nbits);
          rx_shift_reg_next = '0;
          bits_left_next    = nbits;
          rx_en_reg_next    = rx_en;
          spi_cs_n_reg_next = 1'b0;
          busy_next         = 1'b1;
          state_next        = ST_BIT_SETUP;
        end
      end

      ST_BIT_SETUP: begin
        spi_sck_reg_next  = 1'b0;
        spi_mosi_reg_next = tx_shift_reg[MAX_BITS-1];
        state_next        = ST_BIT_HIGH;
      end

      ST_BIT_HIGH: begin
        spi_sck_reg_next = 1'b1;
        if (rx_en_reg) begin
          rx_shift_reg_next = {rx_shift_reg[MAX_BITS-2:0], spi_miso};
        end
        state_next = ST_BIT_LOW;
      end

      ST_BIT_LOW: begin
        spi_sck_reg_next  = 1'b0;
        spi_mosi_reg_next = 1'b0;
        tx_shift_reg_next = {tx_shift_reg[MAX_BITS-2:0], 1'b0};
        bits_left_next    = bits_left - 1'b1;

        if (bits_left == 6'd1) begin
          rx_data_next = rx_shift_reg;
          state_next   = ST_CS_HOLD;
        end else begin
          state_next = ST_BIT_SETUP;
        end
      end

      ST_CS_HOLD: begin
        // Hold CS# low for one extra system clock after the final falling edge.
        spi_cs_n_reg_next = 1'b0;
        spi_sck_reg_next  = 1'b0;
        spi_mosi_reg_next = 1'b0;
        state_next        = ST_DONE;
      end

      ST_DONE: begin
        spi_cs_n_reg_next = 1'b1;
        spi_sck_reg_next  = 1'b0;
        spi_mosi_reg_next = 1'b0;
        busy_next         = 1'b0;
        done_next         = 1'b1;
        state_next        = ST_IDLE;
      end

      default: begin
        state_next = ST_IDLE;
      end
    endcase
  end

endmodule
