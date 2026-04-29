package dma_pkg;

  // Global parameters
  // TT-size build: keep the internal DMA address/length small for area.
  // spi_psram_ctrl zero-extends ADDR_W to the PSRAM's 24-bit wire address phase.
  parameter int ADDR_W = 16;
  parameter int DATA_W = 8;    // Data width (byte-level transfers)
  parameter int LEN_W  = 8;    // Transfer length width (max number of bytes per DMA)
  parameter int N_CH   = 2;    // Number of DMA channels

  // SPI command opcodes (from PSRAM datasheet)
  localparam logic [7:0] SPI_CMD_READ  = 8'h03; // Serial read
  localparam logic [7:0] SPI_CMD_WRITE = 8'h02; // Serial write

  // Control register bit definitions
  localparam int CTRL_START_BIT   = 0; // Start transfer when set
  localparam int CTRL_INC_SRC_BIT = 1; // Increment source address after each transfer
  localparam int CTRL_INC_DST_BIT = 2; // Increment destination address after each transfer

  // DMA controller FSM states (byte-level transfer control)
  typedef enum logic [3:0] {
    DMA_IDLE,         // Waiting for start
    DMA_SELECT_CH,    // Select next active channel (scheduler)
    DMA_LOAD_STATE,   // Load channel state into working registers
    DMA_ISSUE_READ,   // Issue memory read request
    DMA_WAIT_READ,    // Wait for read data
    DMA_ISSUE_WRITE,  // Issue memory write request
    DMA_WAIT_WRITE,   // Wait for write completion
    DMA_UPDATE_STATE, // Update pointers and counters
    DMA_COMPLETE      // Transfer complete
  } dma_state_t;

endpackage
