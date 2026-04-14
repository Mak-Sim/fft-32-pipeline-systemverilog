////////////////////////////////////////////////////////////////////////////////
//
// Filename: fft_tb.sv
//
// Purpose: Testbench for 32-point pipelined FFT (fftmain)
//          Generates a real cosine at bin frequency (k=1)
//          Output waveform for manual inspection
//
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module fft_tb;

    // Parameters from fftmain
    localparam IWIDTH = 16;
    localparam OWIDTH = 19;
    localparam FFT_SIZE = 32;
    localparam CLK_PERIOD = 10; // 10 ns = 100 MHz
    localparam AMPLITUDE = 1000; // Reduced to avoid overflow
    
    // Signals
    logic i_clk = 0;
    logic i_reset = 1;
    logic i_ce = 0;
    logic [2*IWIDTH-1:0] i_sample = 0;
    logic [2*OWIDTH-1:0] o_result;
    logic o_sync;
    
    // Test generation variables
    int sample_count = 0;
    real theta;
    shortint sample_real;
    // Test mode: 0 = DC, 1 = cosine at bin 1
    localparam TEST_MODE = 1;
    
    // Instantiate DUT
    fftmain dut (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_ce(i_ce),
        .i_sample(i_sample),
        .o_result(o_result),
        .o_sync(o_sync)
    );
    
    // Clock generation
    always #(CLK_PERIOD/2) i_clk = ~i_clk;
    
    // Stimulus
    initial begin
        // Initialize waveform dump
        $dumpfile("waveform.vcd");
        $dumpvars(0, fft_tb);
        
        // Release reset after a few clocks
        #(CLK_PERIOD * 2);
        i_reset = 0;
        i_ce = 1;
        
        // Feed 32 samples of test signal
        for (sample_count = 0; sample_count < FFT_SIZE; sample_count++) begin
            if (TEST_MODE == 0) begin
                // DC signal
                sample_real = AMPLITUDE;
            end else begin
                // Cosine at bin 1
                theta = 2.0 * $acos(-1.0) * sample_count / FFT_SIZE; // 2π * n / N
                sample_real = shortint'($cos(theta) * AMPLITUDE);
            end
            i_sample = {sample_real, 16'd0}; // Real part only, imaginary zero
            $display("Input[%0d]: real=%d", sample_count, sample_real);
            #CLK_PERIOD;
        end

        // Feed 32 samples of test signal
        for (sample_count = 0; sample_count < FFT_SIZE; sample_count++) begin
            if (TEST_MODE == 0) begin
                // DC signal
                sample_real = AMPLITUDE;
            end else begin
                // Cosine at bin 1
                theta = 2.0 * $acos(-1.0) * 2 *sample_count / FFT_SIZE; // 2π * n / N
                sample_real = shortint'($cos(theta) * AMPLITUDE);
            end
            i_sample = {sample_real, 16'd0}; // Real part only, imaginary zero
            $display("Input[%0d]: real=%d", sample_count, sample_real);
            #CLK_PERIOD;
        end

        // Feed 32 samples of test signal
        for (sample_count = 0; sample_count < FFT_SIZE; sample_count++) begin
            if (TEST_MODE == 0) begin
                // DC signal
                sample_real = AMPLITUDE;
            end else begin
                // Cosine at bin 1
                theta = 2.0 * $acos(-1.0) * 3 *sample_count / FFT_SIZE; // 2π * n / N
                sample_real = shortint'($cos(theta) * AMPLITUDE);
            end
            i_sample = {sample_real, 16'd0}; // Real part only, imaginary zero
            $display("Input[%0d]: real=%d", sample_count, sample_real);
            #CLK_PERIOD;
        end

        // Feed 32 samples of test signal
        for (sample_count = 0; sample_count < FFT_SIZE; sample_count++) begin
            sample_real = AMPLITUDE;
            i_sample = {sample_real, 16'd0}; // Real part only, imaginary zero
            $display("Input[%0d]: real=%d", sample_count, sample_real);
            #CLK_PERIOD;
        end
        
        // Continue with zeros for another 200 cycles to flush pipeline and observe outputs
        i_sample = 0;
        for (int i = 0; i < 200; i++) begin
            #CLK_PERIOD;
        end
        
        // End simulation
        $display("Simulation completed at time %0t ns", $time);
        $finish;
    end

    // Monitor inputs
    logic signed [IWIDTH-1:0] i_real, i_imag;
    assign i_real = i_sample[2*IWIDTH-1:IWIDTH];
    assign i_imag = i_sample[IWIDTH-1:0];

    // Monitor outputs
    logic signed [OWIDTH-1:0] o_real, o_imag;
    assign o_real = o_result[2*OWIDTH-1:OWIDTH];
    assign o_imag = o_result[OWIDTH-1:0];
    
    // Capture FFT output frame
    logic capture_en = 0;
    logic frame_printed = 0;
    int capture_index = 0;
    logic signed [OWIDTH-1:0] out_frame_real [0:31];
    logic signed [OWIDTH-1:0] out_frame_imag [0:31];
    
    always @(posedge i_clk) begin
        if (i_ce) begin
            if (o_sync) begin
                // Start capture with current output as first bin
                capture_en <= 1;
                frame_printed <= 0;
                capture_index <= 1; // Already capturing bin 0 now
                out_frame_real[0] <= o_real;
                out_frame_imag[0] <= o_imag;
                $display("Capture[0]: real=%d, imag=%d (sync cycle)", o_real, o_imag);
            end else if (capture_en && capture_index < 32) begin
                out_frame_real[capture_index] <= o_real;
                out_frame_imag[capture_index] <= o_imag;
                $display("Capture[%0d]: real=%d, imag=%d", capture_index, o_real, o_imag);
                capture_index <= capture_index + 1;
            end else if (capture_en && capture_index == 32 && !frame_printed) begin
                capture_en <= 0;
                frame_printed <= 1;
                // Print summary
                $display("=== FFT Output Frame ===");
                for (int i = 0; i < 32; i++) begin
                    $display("Bin %2d: real=%6d, imag=%6d", i, out_frame_real[i], out_frame_imag[i]);
                end
                $display("=== End Frame ===");
            end
            
            // Always display non-x outputs
            if (o_sync || o_real !== 'x) begin
                $display("Time %0t: sample=%d, out_real=%d, out_imag=%d, sync=%b", 
                         $time, sample_count, o_real, o_imag, o_sync);
            end
        end
    end

endmodule
