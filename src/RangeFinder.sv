module RangeFinder #(parameter int WIDTH=8) (
  input  logic [WIDTH-1:0] data_in,
  input  logic             clock, reset,
  input  logic             go, finish,
  output logic [WIDTH-1:0] range,
  output logic             error
);

  typedef enum logic [1:0] {ST_IDLE, ST_MEASURE, ST_DONE, ST_ERROR} state_t;
  state_t state, next_state;

  // Edge detection (since it seems like this is expected)
  logic go_q, finish_q;
  logic go_re, finish_re;

  always_ff @(posedge clock or posedge reset) begin
    if (reset) begin
      go_q     <= 1'b0;
      finish_q <= 1'b0;
    end else begin
      go_q     <= go;
      finish_q <= finish;
    end
  end

  assign go_re = go & ~go_q;
  assign finish_re = finish & ~finish_q;
  

  logic [WIDTH-1:0] min, max;
  logic [WIDTH-1:0] curr_min, curr_max;

  // Range calc - value only needs to be correct on finish_re
  assign curr_min = (data_in < min) ? data_in : min;
  assign curr_max = (data_in > max) ? data_in : max;
  assign range = curr_max - curr_min;
  

  // State register
  always_ff @(posedge clock, posedge reset) begin
    if (reset)
      state <= ST_IDLE;
    else
      state <= next_state;
  end

  // Next state logic and error flag setting
  always_comb begin
    // default
    error = 1'b0;
    next_state = state;

    unique case (state)
      ST_IDLE: begin
        if (finish) begin
          next_state = ST_ERROR;
          error = 1'b1;
        end else if (go)
          next_state = ST_MEASURE;
        else
          next_state = ST_IDLE;
      end

      ST_MEASURE: begin
        if (go_re) begin
          next_state = ST_ERROR;
          error = 1'b1;
        end else if (finish)
          next_state = ST_DONE;
        else
          next_state = ST_MEASURE;
      end

      ST_DONE: begin
        if (go_re)
          next_state = ST_MEASURE;
        else if (!finish)
          next_state = ST_IDLE;
        else
          next_state = ST_DONE;
      end

      ST_ERROR: begin
        error = 1'b1;
        if (go && !finish)
          next_state = ST_MEASURE;
        else
          next_state = ST_ERROR;
      end

      default: next_state = ST_IDLE;
    endcase
  end

  // min max computation
  always_ff @(posedge clock, posedge reset) begin
    if (reset) begin
      min <= '0;
      max <= '0;
    end else begin
      unique case (state)
        ST_IDLE: begin
          if (go && !finish) begin
            min <= data_in;
            max <= data_in;
          end
        end
        ST_MEASURE: begin
          min <= curr_min;
          max <= curr_max;
        end
        ST_DONE: begin
          if (go && !finish) begin
            min <= data_in;
            max <= data_in;
          end
        end
        ST_ERROR: begin
          if (go && !finish) begin
            min <= data_in;
            max <= data_in;
          end
        end
        default: begin
          // No updates
        end
      endcase
    end
  end

endmodule
