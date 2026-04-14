////////////////////////////////////////////////////////////////////////////////
//
// Filename:	fftstage.v
// {{{
// Project:	A General Purpose Pipelined FFT Implementation
//
// Purpose:	This file is (almost) a Verilog source file.  It is meant to
//		be used by a FFT core compiler to generate FFTs which may be
//	used as part of an FFT core.  Specifically, this file encapsulates
//	the options of an FFT-stage.  For any 2^N length FFT, there shall be
//	(N-1) of these stages.
//
//
// Operation:
// 	Given a stream of values, operate upon them as though they were
// 	value pairs, x[n] and x[n+N/2].  The stream begins when n=0, and ends
// 	when n=N/2-1 (i.e. there's a full set of N values).  When the value
// 	x[0] enters, the synchronization input, i_sync, must be true as well.
//
// 	For this stream, produce outputs
// 	y[n    ] = x[n] + x[n+N/2], and
// 	y[n+N/2] = (x[n] - x[n+N/2]) * c[n],
// 			where c[n] is a complex coefficient found in the
// 			external memory file COEFFILE.
// 	When y[0] is output, a synchronization bit o_sync will be true as
// 	well, otherwise it will be zero.
//
// 	Most of the work to do this is done within the butterfly, whether the
// 	hardware accelerated butterfly (uses a DSP) or not.
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
// }}}
// Copyright (C) 2015-2024, Gisselquist Technology, LLC
// {{{
// This file is part of the general purpose pipelined FFT project.
//
// The pipelined FFT project is free software (firmware): you can redistribute
// it and/or modify it under the terms of the GNU Lesser General Public License
// as published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// The pipelined FFT project is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTIBILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser
// General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this program.  (It's in the $(ROOT)/doc directory.  Run make
// with no target there if the PDF file isn't present.)  If not, see
// <http://www.gnu.org/licenses/> for a copy.
// }}}
// License:	LGPL, v3, as defined and found on www.gnu.org,
// {{{
//		http://www.gnu.org/licenses/lgpl.html
//
// }}}
////////////////////////////////////////////////////////////////////////////////
//
//
`default_nettype	none
//
module	fftstage #(
		// {{{
		parameter	IWIDTH=16,CWIDTH=20,OWIDTH=17,
		// Parameters specific to the core that should be changed when
		// this core is built ... Note that the minimum LGSPAN (the base
		// two log of the span, or the base two log of the current FFT
		// size) is 3.  Smaller spans (i.e. the span of 2) must use the
		// dbl laststage module.
		// Verilator lint_off UNUSED
		parameter	LGSPAN=4, BFLYSHIFT=0, // LGWIDTH=5
		parameter [0:0]	OPT_HWMPY = 1,
		// Clocks per CE.  If your incoming data rate is less than 50%
		// of your clock speed, you can set CKPCE to 2'b10, make sure
		// there's at least one clock between cycles when i_ce is high,
		// and then use two multiplies instead of three.  Setting CKPCE
		// to 2'b11, and insisting on at least two clocks with i_ce low
		// between cycles with i_ce high, then the hardware optimized
		// butterfly code will used one multiply instead of two.
		parameter	CKPCE = 1,
		// The COEFFILE parameter contains the name of the file
		// containing the FFT twiddle factors
		parameter	COEFFILE="cmem_32.hex"
	) (
		// {{{
		input logic				i_clk, i_reset,
							i_ce, i_sync,
		input logic	[(2*IWIDTH-1):0]	i_data,
		output logic	[(2*OWIDTH-1):0]	o_data,
		output logic				o_sync

		// }}}
	);

	// Local signal definitions
	// {{{
	// I am using the prefixes
	// 	ib_*	to reference the inputs to the butterfly, and
	// 	ob_*	to reference the outputs from the butterfly
	logic	wait_for_sync;
	logic	[(2*IWIDTH-1):0]	ib_a, ib_b;
	logic	[(2*CWIDTH-1):0]	ib_c;
	logic	ib_sync;

	logic	b_started;
	logic	ob_sync;
	logic	[(2*OWIDTH-1):0]	ob_a, ob_b;

	// cmem is defined as an array of real and complex values,
	// where the top CWIDTH bits are the real value and the bottom
	// CWIDTH bits are the imaginary value.
	//
	// cmem[i] = { (2^(CWIDTH-2)) * cos(2*pi*i/(2^LGWIDTH)),
	//		(2^(CWIDTH-2)) * sin(2*pi*i/(2^LGWIDTH)) };
	//
	logic	[(2*CWIDTH-1):0]	cmem [0:((1<<LGSPAN)-1)];

	initial	$readmemh(COEFFILE,cmem);

	logic	[(LGSPAN):0]		iaddr;
	logic	[(2*IWIDTH-1):0]	imem	[0:((1<<LGSPAN)-1)];

	logic	[LGSPAN:0]		oaddr;
	logic	[(2*OWIDTH-1):0]	omem	[0:((1<<LGSPAN)-1)];

	logic				idle;
	logic	[(LGSPAN-1):0]		nxt_oaddr;
	logic	[(2*OWIDTH-1):0]	pre_ovalue;
	// }}}

	// wait_for_sync, iaddr
	// {{{
	initial wait_for_sync = 1'b1;
	initial iaddr = 0;
	always_ff @(posedge i_clk)
	if (i_reset)
	begin
		wait_for_sync <= 1'b1;
		iaddr <= 0;
	end else if ((i_ce)&&((!wait_for_sync)||(i_sync)))
	begin
		//
		// First step: Record what we're not ready to use yet
		//
		iaddr <= iaddr + { {(LGSPAN){1'b0}}, 1'b1 };
		wait_for_sync <= 1'b0;
	end
	// }}}

	// Write to imem
	// {{{
	always_ff @(posedge i_clk) // Need to make certain here that we don't read
	if ((i_ce)&&(!iaddr[LGSPAN])) // and write the same address on
		imem[iaddr[(LGSPAN-1):0]] <= i_data; // the same clk
	// }}}

	// ib_sync
	// {{{
	// Now, we have all the inputs, so let's feed the butterfly
	//
	// ib_sync is the synchronization bit to the butterfly.  It will
	// be tracked within the butterfly, and used to create the o_sync
	// value when the results from this output are produced
	initial ib_sync = 1'b0;
	always_ff @(posedge i_clk)
	if (i_reset)
		ib_sync <= 1'b0;
	else if (i_ce)
	begin
		// Set the sync to true on the very first
		// valid input in, and hence on the very
		// first valid data out per FFT.
		ib_sync <= (iaddr==(1<<(LGSPAN)));
	end
	// }}}

	// ib_a, ib_b, ib_c
	// {{{
	// Read the values from our input memory, and use them to feed
	// first of two butterfly inputs
	always_ff @(posedge i_clk)
	if (i_ce)
	begin
		// One input from memory, ...
		ib_a <= imem[iaddr[(LGSPAN-1):0]];
		// One input clocked in from the top
		ib_b <= i_data;
		// and the coefficient or twiddle factor
		ib_c <= cmem[iaddr[(LGSPAN-1):0]];
	end
	// }}}

	////////////////////////////////////////////////////////////////////////
	//
	// Instantiate the butterfly
	// {{{
	////////////////////////////////////////////////////////////////////////

	butterfly #(
			// {{{
			.IWIDTH(IWIDTH),
			.CWIDTH(CWIDTH),
			.OWIDTH(OWIDTH),
			.CKPCE(CKPCE),
			.SHIFT(BFLYSHIFT)
			// }}}
		) bfly(
			// {{{
			.i_clk(i_clk), .i_reset(i_reset), .i_ce(i_ce),
			.i_coef( (idle && !i_ce)? {(2*CWIDTH){1'b0}} :ib_c),
			.i_left( (idle && !i_ce)? {(2*IWIDTH){1'b0}} :ib_a),
			.i_right((idle && !i_ce)? {(2*IWIDTH){1'b0}} :ib_b),
			.i_aux(ib_sync && i_ce),
			.o_left(ob_a), .o_right(ob_b), .o_aux(ob_sync)
			// }}}
		);

	// }}}

	// oaddr, o_sync, b_started
	// {{{
	// Next step: recover the outputs from the butterfly
	//
	// The first output can go immediately to the output of this routine
	// The second output must wait until this time in the idle cycle
	// oaddr is the output memory address, keeping track of where we are
	// in this output cycle.
	initial oaddr     = 0;
	initial o_sync    = 0;
	initial b_started = 0;
	always_ff @(posedge i_clk)
	if (i_reset)
	begin
		oaddr     <= 0;
		o_sync    <= 0;
		// b_started will be true once we've seen the first ob_sync
		b_started <= 0;
	end else if (i_ce)
	begin
		o_sync <= (!oaddr[LGSPAN])?ob_sync : 1'b0;
		if (ob_sync||b_started)
			oaddr <= oaddr + 1'b1;
		if ((ob_sync)&&(!oaddr[LGSPAN]))
			// If b_started is true, then a butterfly output
			// is available
			b_started <= 1'b1;
	end
	// }}}

	// nxt_oaddr
	// {{{
	always_ff @(posedge i_clk)
	if (i_ce)
		nxt_oaddr[0] <= oaddr[0];
	generate if (LGSPAN>1)
	begin : WIDE_LGSPAN

		always_ff @(posedge i_clk)
		if (i_ce)
			nxt_oaddr[LGSPAN-1:1] <= oaddr[LGSPAN-1:1] + 1'b1;

	end endgenerate
	// }}}

	// omem
	// {{{
	// Only write to the memory on the first half of the outputs
	// We'll use the memory value on the second half of the outputs
	always_ff @(posedge i_clk)
	if ((i_ce)&&(!oaddr[LGSPAN]))
		omem[oaddr[(LGSPAN-1):0]] <= ob_b;
	// }}}

	// pre_ovalue
	// {{{
	always_ff @(posedge i_clk)
	if (i_ce)
		pre_ovalue <= omem[nxt_oaddr[(LGSPAN-1):0]];
	// }}}

	// o_data
	// {{{
	always_ff @(posedge i_clk)
	if (i_ce)
		o_data <= (!oaddr[LGSPAN]) ? ob_a : pre_ovalue;
	// }}}


endmodule
