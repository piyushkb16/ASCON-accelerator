`timescale 1ns/1ps

// Self-checking tests for the public round and permutation interfaces.
// Golden files are produced independently from the pinned upstream C reference.
module tb_ascon;
  localparam integer MAX_VECTORS = 8192;
  logic clk_i = 1'b0;
  logic rst_ni = 1'b1;
  logic start_i = 1'b0;
  logic p8_i = 1'b0;
  logic [319:0] state_i = '0;
  wire ready_o, busy_o, done_o;
  wire [319:0] state_o;
  logic [319:0] round_state_i = '0;
  logic [7:0] round_constant_i = '0;
  wire [319:0] round_state_o;

  integer permutation_rounds [0:MAX_VECTORS-1];
  reg [319:0] permutation_input [0:MAX_VECTORS-1];
  reg [319:0] permutation_expected [0:MAX_VECTORS-1];
  integer permutation_count = 0;
  integer round_count = 0;
  integer transactions = 0;
  integer checks = 0;
  integer p8_sample = -1;
  integer p12_sample = -1;
  reg [319:0] last_output = '0;

  ascon_round u_round (
    .state_i(round_state_i),
    .round_constant_i(round_constant_i),
    .state_o(round_state_o)
  );
  ascon_permutation u_permutation (
    .clk_i(clk_i), .rst_ni(rst_ni), .start_i(start_i),
    .p8_i(p8_i), .state_i(state_i),
    .ready_o(ready_o), .busy_o(busy_o), .done_o(done_o),
    .state_o(state_o)
  );
  always #5 clk_i = ~clk_i;

  task automatic require(input logic condition, input string message);
    begin
      checks = checks + 1;
      if (condition !== 1'b1)
        $fatal(1, "%s (time=%0t)", message, $time);
    end
  endtask

  // Sample after NBA updates; drive all synchronous controls on falling edges.
  task automatic tick;
    begin
      @(posedge clk_i);
      #1;
    end
  endtask

  task automatic expect_idle(input string context_message);
    begin
      require(ready_o === 1'b1, {context_message, ": ready"});
      require(busy_o === 1'b0, {context_message, ": busy"});
      require(done_o === 1'b0, {context_message, ": done"});
      require(state_o === last_output, {context_message, ": output stable"});
    end
  endtask

  task automatic expect_active(input string context_message);
    begin
      require(ready_o === 1'b0, {context_message, ": ready"});
      require(busy_o === 1'b1, {context_message, ": busy"});
      require(done_o === 1'b0, {context_message, ": done"});
      require(state_o === last_output, {context_message, ": output stable"});
    end
  endtask

  task automatic expect_result(input integer index);
    begin
      require(ready_o === 1'b1, "completion: ready");
      require(busy_o === 1'b0, "completion: busy");
      require(done_o === 1'b1, "completion: done");
      if (state_o !== permutation_expected[index]) begin
        $display("vector=%0d rounds=%0d", index, permutation_rounds[index]);
        $display("input    %080h", permutation_input[index]);
        $display("expected %080h", permutation_expected[index]);
        $display("actual   %080h", state_o);
        $fatal(1, "permutation mismatch");
      end
      checks = checks + 1;
      last_output = permutation_expected[index];
      transactions = transactions + 1;
    end
  endtask

  // Return on the completion edge. Calling this again immediately launches the
  // next operation on the very next rising edge (no mandatory idle bubble).
  task automatic run_vector(input integer index, input logic noisy_busy_inputs);
    integer cycle;
    begin
      @(negedge clk_i);
      start_i = 1'b1;
      p8_i = (permutation_rounds[index] == 8);
      state_i = permutation_input[index];
      tick();
      expect_active("acceptance performs no round");
      for (cycle = 1; cycle <= permutation_rounds[index]; cycle = cycle + 1) begin
        @(negedge clk_i);
        // Exercise capture of all inputs. Busy start pulses, including the last
        // round's edge, must be ignored; only idle start requests are accepted.
        start_i = noisy_busy_inputs;
        state_i = ~state_i;
        p8_i = ~p8_i;
        tick();
        if (cycle < permutation_rounds[index])
          expect_active("permutation before scheduled completion");
        else
          expect_result(index);
      end
    end
  endtask

  task automatic quiet_idle(input integer cycles);
    integer cycle;
    begin
      @(negedge clk_i);
      start_i = 1'b0;
      for (cycle = 0; cycle < cycles; cycle = cycle + 1) begin
        state_i = ~state_i;
        p8_i = ~p8_i;
        tick();
        expect_idle("idle / done pulse width");
        if (cycle + 1 < cycles)
          @(negedge clk_i);
      end
    end
  endtask

  // Holding start high across completion is a fresh request at the first idle
  // edge. Input changes while busy must not affect the operation in flight.
  task automatic held_start_test;
    integer cycle;
    begin
      @(negedge clk_i);
      start_i = 1'b1;
      p8_i = 1'b0;
      state_i = permutation_input[p12_sample];
      tick();
      expect_active("held start first acceptance");
      for (cycle = 1; cycle <= 12; cycle = cycle + 1) begin
        @(negedge clk_i);
        state_i = permutation_input[p8_sample];
        p8_i = 1'b1;
        tick();
        if (cycle < 12)
          expect_active("held start first operation");
        else
          expect_result(p12_sample);
      end
      // No control changes: held start accepts the second transaction here.
      tick();
      expect_active("held start accepts on next idle edge");
      for (cycle = 1; cycle <= 8; cycle = cycle + 1) begin
        @(negedge clk_i);
        start_i = 1'b0;
        state_i = ~state_i;
        p8_i = 1'b0;
        tick();
        if (cycle < 8)
          expect_active("held start second operation");
        else
          expect_result(p8_sample);
      end
      quiet_idle(2);
    end
  endtask

  // Abort both early and immediately before scheduled completion. Reset is
  // deliberately asserted between rising edges to verify asynchronous clearing.
  task automatic reset_abort_test(input integer index, input integer rounds_to_run);
    integer cycle;
    begin
      @(negedge clk_i);
      start_i = 1'b1;
      p8_i = (permutation_rounds[index] == 8);
      state_i = permutation_input[index];
      tick();
      expect_active("reset test acceptance");
      @(negedge clk_i);
      start_i = 1'b0;
      for (cycle = 0; cycle < rounds_to_run; cycle = cycle + 1) begin
        tick();
        expect_active("operation before abort");
      end
      #1;
      rst_ni = 1'b0;
      last_output = '0;
      #1;
      expect_idle("asynchronous reset cancels operation");
      // Start during asserted reset must have no effect.
      start_i = 1'b1;
      tick();
      expect_idle("held reset ignores start");
      @(negedge clk_i);
      start_i = 1'b0;
      rst_ni = 1'b1;
      for (cycle = 0; cycle < 14; cycle = cycle + 1) begin
        tick();
        expect_idle("no stale completion after reset");
      end
    end
  endtask

  integer fd, fields, index, round_index;
  reg [319:0] input_value, expected_value;
  initial begin
    // Bound the run so a broken DUT cannot leave simulation hanging forever.
    #2000000;
    $fatal(1, "testbench timeout");
  end

  initial begin
    // Generate a real falling reset edge; declaration initialization alone
    // does not reliably trigger asynchronous reset in every simulator.
    #1;
    rst_ni = 1'b0;
    #1;
    expect_idle("power-on reset");
    #1;
    rst_ni = 1'b1;
    tick();
    expect_idle("initial idle");

    fd = $fopen("vectors/round.txt", "r");
    require(fd != 0, "open vectors/round.txt");
    while (!$feof(fd)) begin
      fields = $fscanf(fd, "%d %h %h\n", round_index, input_value, expected_value);
      if (fields == 3) begin
        require(round_index >= 0 && round_index <= 11, "valid round vector index");
        round_state_i = input_value;
        round_constant_i = 8'hf0 - round_index * 8'h0f;
        #1;
        if (round_state_o !== expected_value) begin
          $display("round vector=%0d index=%0d constant=%02h", round_count, round_index, round_constant_i);
          $display("input    %080h", input_value);
          $display("expected %080h", expected_value);
          $display("actual   %080h", round_state_o);
          $fatal(1, "round mismatch");
        end
        checks = checks + 1;
        round_count = round_count + 1;
      end else if (fields != -1) begin
        $fatal(1, "malformed round vector line");
      end
    end
    $fclose(fd);
    require(round_count >= 12, "round vector coverage");

    fd = $fopen("vectors/permutation.txt", "r");
    require(fd != 0, "open vectors/permutation.txt");
    while (!$feof(fd)) begin
      fields = $fscanf(fd, "%d %h %h\n", round_index, input_value, expected_value);
      if (fields == 3) begin
        require(permutation_count < MAX_VECTORS, "permutation vector array capacity");
        require(round_index == 8 || round_index == 12, "valid permutation round count");
        permutation_rounds[permutation_count] = round_index;
        permutation_input[permutation_count] = input_value;
        permutation_expected[permutation_count] = expected_value;
        if (round_index == 8 && p8_sample == -1) p8_sample = permutation_count;
        if (round_index == 12 && p12_sample == -1) p12_sample = permutation_count;
        permutation_count = permutation_count + 1;
      end else if (fields != -1) begin
        $fatal(1, "malformed permutation vector line");
      end
    end
    $fclose(fd);
    require(permutation_count >= 2, "permutation vectors present");
    require(p8_sample >= 0 && p12_sample >= 0, "both permutation modes present");

    for (index = 0; index < permutation_count; index = index + 1)
      run_vector(index, (index % 2) == 0);
    quiet_idle(4);
    held_start_test();
    reset_abort_test(p12_sample, 3);
    run_vector(p8_sample, 1'b1);
    quiet_idle(2);
    reset_abort_test(p8_sample, 7);
    run_vector(p12_sample, 1'b0);
    quiet_idle(4);

    // Reset while done is asserted must also clear the result and pulse.
    run_vector(p8_sample, 1'b0);
    #1;
    rst_ni = 1'b0;
    last_output = '0;
    #1;
    expect_idle("reset on completion pulse");
    @(negedge clk_i);
    start_i = 1'b0;
    rst_ni = 1'b1;
    quiet_idle(3);

    $display("PASS: %0d round vectors, %0d permutation vectors, %0d completed transactions, %0d checks", round_count, permutation_count, transactions, checks);
    $display("PASS: exact p8/p12 latency, back-to-back acceptance, ignored busy starts, captured inputs, held start, reset abort/recovery, done pulse, output retention");
    $finish;
  end
endmodule
