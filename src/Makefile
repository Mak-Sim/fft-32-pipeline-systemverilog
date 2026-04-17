# Makefile for Icarus Verilog simulation of pipelined FFT
# SystemVerilog conversion

# Tools
IVERILOG := iverilog
VVP := vvp
GTKWAVE := gtkwave
SURFER := surfer
SURFER_COMMANDFILE := fft_tb.sucl

# Flags
IVERILOG_FLAGS := -g2012 -Wall
VVP_FLAGS := -v

# Files
SV_SOURCES := $(wildcard *.sv)
SV_EXCLUDE_TB := $(filter-out %_tb.sv, $(SV_SOURCES))

# Testbench configurations
FFT_TB_SOURCE := fft_tb.sv
FFT_TOP_MODULE := fft_tb
FFT_EXEC := fft.bin
FFT_VCD_FILE := fft_tb.vcd
FFT_SURFER_STATE := fft_tb.surf.ron

LASTSTAGE_TB_SOURCE := laststage_tb.sv
LASTSTAGE_TOP_MODULE := laststage_tb
LASTSTAGE_EXEC := laststage.bin
LASTSTAGE_VCD_FILE := laststage_tb.vcd
LASTSTAGE_SURFER_STATE := laststage_tb.surf.ron

# Generic testbench pattern (for future expansion)
TB_SOURCES := $(wildcard *_tb.sv)

.PHONY: all sim fft_sim laststage_sim wave fft_wave laststage_wave clean help lint

all: fft_sim

# Main FFT testbench targets
fft_sim: $(FFT_VCD_FILE)

$(FFT_VCD_FILE): $(FFT_EXEC)
	$(VVP) $(VVP_FLAGS) $<

$(FFT_EXEC): $(SV_SOURCES)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ -s $(FFT_TOP_MODULE) $(SV_SOURCES)

fft_wave: $(FFT_VCD_FILE)
	$(SURFER) -s $(FFT_SURFER_STATE) $(FFT_VCD_FILE) &

# Laststage testbench targets
laststage_sim: $(LASTSTAGE_VCD_FILE)

$(LASTSTAGE_VCD_FILE): $(LASTSTAGE_EXEC)
	$(VVP) $(VVP_FLAGS) $<

$(LASTSTAGE_EXEC): $(SV_SOURCES)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ -s $(LASTSTAGE_TOP_MODULE) $(SV_SOURCES)

laststage_wave: $(LASTSTAGE_VCD_FILE)
	$(SURFER) -s $(LASTSTAGE_SURFER_STATE) $(LASTSTAGE_VCD_FILE) &

# Legacy aliases
sim: fft_sim
wave: fft_wave

# Surfer targets (FFT only)
surfer: $(FFT_VCD_FILE)
	$(SURFER) $(FFT_VCD_FILE) -c $(SURFER_COMMANDFILE) &

clean:
	rm -f $(FFT_EXEC) $(FFT_VCD_FILE) \
	      $(LASTSTAGE_EXEC) $(LASTSTAGE_VCD_FILE) \
	      *.vcd *.log *.jou

# Quick syntax check for all testbenches
lint:
	@echo "=== Syntax check for FFT testbench ==="
	$(IVERILOG) $(IVERILOG_FLAGS) -t null -s $(FFT_TOP_MODULE) $(SV_SOURCES) 2>&1 | head -20
	@echo ""
	@echo "=== Syntax check for laststage testbench ==="
	$(IVERILOG) $(IVERILOG_FLAGS) -t null -s $(LASTSTAGE_TOP_MODULE) $(SV_SOURCES) 2>&1 | head -20

# Help
help:
	@echo "Available targets:"
	@echo "  make fft_sim        - Run FFT simulation (legacy: make sim)"
	@echo "  make fft_wave       - Run FFT simulation and open waveform (legacy: make wave)"
	@echo "  make laststage_sim  - Run laststage module simulation"
	@echo "  make laststage_wave - Run laststage simulation and open waveform"
	@echo "  make lint           - Check syntax for all testbenches"
	@echo "  make clean          - Remove all generated files"
	@echo "  make help           - Show this message"
	@echo ""
	@echo "Legacy targets (for backward compatibility):"
	@echo "  make sim            - Alias for fft_sim"
	@echo "  make wave           - Alias for fft_wave"
