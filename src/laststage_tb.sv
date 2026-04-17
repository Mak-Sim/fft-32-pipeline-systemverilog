////////////////////////////////////////////////////////////////////////////////
//
// Filename: laststage_tb.sv
//
// Purpose: Testbench for laststage module (final butterfly stage of DIF FFT)
//          Tests with predefined vectors from README and random vectors
//          Verifies latency, sync timing, and correct sum/difference operations
//
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module laststage_tb;

    // Parameters from fft_tb.sv
    localparam IWIDTH = 16;
    localparam OWIDTH = 19;
    localparam SHIFT = 0;
    localparam CLK_PERIOD = 10; // 10 ns = 100 MHz

    // Signals
    logic i_clk = 0;
    logic i_reset = 1;
    logic i_ce = 0;
    logic i_sync = 0;
    logic [(2*IWIDTH-1):0] i_val = 0;
    logic [(2*OWIDTH-1):0] o_val;
    logic o_sync;

    // Test control
    int test_count = 0;
    int error_count = 0;
    int total_tests = 0;

    // Expected results storage (size for 4 predefined + 10 random pairs = 14*2 = 28)
    logic signed [OWIDTH-1:0] expected_real [0:31];
    logic signed [OWIDTH-1:0] expected_imag [0:31];
    int expected_index = 0;
    int output_index = 0;

    // Monitor signals
    logic signed [IWIDTH-1:0] i_real, i_imag;
    logic signed [OWIDTH-1:0] o_real, o_imag;
    assign i_real = i_val[(2*IWIDTH-1):IWIDTH];
    assign i_imag = i_val[IWIDTH-1:0];
    assign o_real = o_val[(2*OWIDTH-1):OWIDTH];
    assign o_imag = o_val[OWIDTH-1:0];

    // Instantiate DUT
    laststage #(
        .IWIDTH(IWIDTH),
        .OWIDTH(OWIDTH),
        .SHIFT(SHIFT)
    ) dut (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_ce(i_ce),
        .i_sync(i_sync),
        .i_val(i_val),
        .o_val(o_val),
        .o_sync(o_sync)
    );

    // Clock generation
    always #(CLK_PERIOD/2) i_clk = ~i_clk;

    initial begin
        // End simulation
        #(CLK_PERIOD * 1024);
        $display("Totall time limit");
        $finish;
    end

    // Main stimulus
    initial begin
        // Initialize waveform dump
        $dumpfile("laststage_tb.vcd");
        $dumpvars(0, laststage_tb);

        // Release reset and enable
        #(CLK_PERIOD * 2);
        i_reset = 0;
        i_ce = 1;

        $display("==========================================");
        $display("Starting laststage testbench");
        $display("IWIDTH=%0d, OWIDTH=%0d, SHIFT=%0d", IWIDTH, OWIDTH, SHIFT);
        $display("==========================================");

        // Test 1: Single predefined pair test
        $display("\n=== Test 1: Single pair test ===");

        // Send first sample with sync
        i_sync = 1;
        i_val = {16'd100, 16'd50};
        #CLK_PERIOD;

        // Send second sample
        i_val = {16'd40, 16'd10};
        #CLK_PERIOD;

        // Send third example
        i_val = {-16'd100, 16'd0};
        #CLK_PERIOD;

        // Send third example
        i_val = {16'd100, 16'd0};
        #CLK_PERIOD;

        // Stop feeding data to avoid extra pairs
        i_val = 0;
        i_sync = 0;
    end

    initial begin

        // Wait for o_sync to indicate sum output
        while (o_sync !== 1'b1) #CLK_PERIOD;
        // Store expected sum
        expected_real[expected_index] = 140;
        expected_imag[expected_index] = 60;
        expected_index++;

        // Wait one cycle for diff output
        #CLK_PERIOD;
        // Store expected diff
        expected_real[expected_index] = 60;
        expected_imag[expected_index] = 40;
        expected_index++;

        // Wait one cycle for diff output
        #CLK_PERIOD;
        // Store expected diff
        expected_real[expected_index] = 0;
        expected_imag[expected_index] = 0;
        expected_index++;

        // Wait one cycle for diff output
        #CLK_PERIOD;
        // Store expected diff
        expected_real[expected_index] = -200;
        expected_imag[expected_index] = 0;
        expected_index++;

        test_count += 4;
        total_tests += 4;
        $display("Single pair test: expected sum=140+j60, diff=60+j40");

        // Wait a few more cycles for outputs to be checked
        #(CLK_PERIOD * 2);

        // Test 2: Sync signal timing
        $display("\n=== Test 3: Sync signal timing ===");
        test_sync_timing();

        // Test 3: Reset behavior
        $display("\n=== Test 4: Reset behavior ===");
        test_reset();

        // Summary
        $display("\n==========================================");
        $display("Test Summary:");
        $display("  Total tests run: %0d", test_count);
        $display("  Errors detected: %0d", error_count);
        $display("  Total pairs tested: %0d", total_tests/2);

        if (error_count == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("FAILED: %0d errors found", error_count);
        end
        $display("==========================================");

        // End simulation
        #(CLK_PERIOD * 10);
        $finish;
    end

    // Task to test sync signal timing
    task test_sync_timing();
        int sync_detected = 0;

        // Send sync and monitor output sync
        i_sync = 1;
        i_val = {16'd100, 16'd50};
        #CLK_PERIOD;
        i_sync = 0;
        i_val = {16'd40, 16'd10};
        #CLK_PERIOD;
        // Stop feeding data to avoid extra pairs
        i_val = 0;

        // Monitor o_sync for next 10 cycles
        for (int i = 0; i < 10; i++) begin
            #CLK_PERIOD;
            if (o_sync) begin
                sync_detected++;
                $display("  o_sync detected at cycle %0d after i_sync", i);
            end
        end

        if (sync_detected == 1) begin
            $display("  Sync timing PASS: o_sync appeared exactly once");
        end else begin
            $display("  Sync timing FAIL: o_sync appeared %0d times (expected 1)", sync_detected);
            error_count++;
        end
    endtask

    // Task to test reset behavior
    task test_reset();
        // Apply reset while module is active
        i_reset = 1;
        #(CLK_PERIOD * 2);
        i_reset = 0;

        // Check that outputs are clean after reset
        #CLK_PERIOD;
        if (o_sync !== 1'b0) begin
            $display("  Reset FAIL: o_sync not cleared");
            error_count++;
        end else begin
            $display("  Reset PASS: outputs cleared after reset");
        end
    endtask

    // Debug: print signals each clock with sync
    always @(posedge i_clk) begin
        if (i_ce & (i_sync | o_sync)) begin
            $display("CLK %0t: i_val=%0d+j%0d, i_sync=%b, o_val=%0d+j%0d, o_sync=%b, expected_index=%0d, output_index=%0d",
                     $time, i_real, i_imag, i_sync, o_real, o_imag, o_sync, expected_index, output_index);
        end
    end

    // Monitor and check outputs
    always @(posedge i_clk) begin
        if (i_ce && !i_reset) begin
            // Check outputs when we have expected values
            if (output_index < expected_index) begin
                if (o_real !== expected_real[output_index] || 
                    o_imag !== expected_imag[output_index]) begin
                    $display("ERROR at output %0d: expected %0d+j%0d, got %0d+j%0d",
                             output_index, expected_real[output_index], 
                             expected_imag[output_index], o_real, o_imag);
                    error_count++;
                end else begin
                    $display("OK output %0d: %0d+j%0d (sync=%b)",
                             output_index, o_real, o_imag, o_sync);
                end
                output_index++;
            end
        end
    end

endmodule