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

  // SPI controller FSM states (transaction-level control)
  typedef enum logic [2:0] {
    SPI_IDLE,              // Idle, waiting for request
    SPI_ASSERT_CS,         // Assert chip select (start transaction)
    SPI_SHIFT_CMD,         // Shift out command byte
    SPI_SHIFT_ADDR,        // Shift out address
    SPI_SHIFT_READ_DATA,   // Shift in read data
    SPI_SHIFT_WRITE_DATA,  // Shift out write data
    SPI_DEASSERT_CS,       // Deassert chip select (end transaction)
    SPI_DONE               // Transaction complete
  } spi_state_t;

  // DMA configuration registers (programmed by CPU/config interface)
  typedef struct packed {
    logic [ADDR_W-1:0] src_base; // Base source address
    logic [ADDR_W-1:0] dst_base; // Base destination address
    logic [LEN_W-1:0]  len;      // Number of bytes to transfer
    logic              inc_src;  // If 1: increment source address each transfer
    logic              inc_dst;  // If 1: increment destination address each transfer
    logic              start_en; // Channel enabled / ready to start
  } dma_cfg_t;

  // DMA runtime state (mutable during transfer)
  typedef struct packed {
    logic [ADDR_W-1:0] src_cur;  // Current source address pointer
    logic [ADDR_W-1:0] dst_cur;  // Current destination address pointer
    logic [LEN_W-1:0]  len_rem;  // Remaining bytes to transfer
    logic              inc_src;  // Latched increment mode (copied from cfg)
    logic              inc_dst;  // Latched increment mode (copied from cfg)
    logic              active;   // Channel is currently active
    logic              done;     // Transfer completed
  } dma_chan_state_t;

  // Memory request (DMA --> SPI/memory controller)
  typedef struct packed {
    logic              valid; // Request is valid
    logic              rw;    // 0 = read, 1 = write
    logic [ADDR_W-1:0] addr;  // Address for access
    logic [DATA_W-1:0] wdata; // Write data (valid if rw = 1)
  } mem_req_t;

  // Memory response (SPI/memory controller --> DMA)
  typedef struct packed {
    logic              ready; // Memory can accept new request
    logic              valid; // Read data is valid
    logic [DATA_W-1:0] rdata; // Read data (valid if valid = 1)
  } mem_rsp_t;

endpackage
