////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	./fft-core-simple/longbimpy.v
// {{{
// Project:	A General Purpose Pipelined FFT Implementation
//
// Purpose:	A portable shift and add multiply, built with the knowledge
//	of the existence of a six bit LUT and carry chain.  That knowledge
//	allows us to multiply two bits from one value at a time against all
//	of the bits of the other value.  This sub multiply is called the
//	bimpy.
//
//	For minimal processing delay, make the first parameter the one with
//	the least bits, so that AWIDTH <= BWIDTH.
//
//
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
`timescale 1ns/1ps
//
module	longbimpy #(
		// {{{
		parameter	IAW=8,	// The width of i_a, min width is 5
				IBW=12,	// The width of i_b, can be anything
			// The following three parameters should not be changed
			// by any implementation, but are based upon hardware
			// and the above values:
			// OW=IAW+IBW;	// The output width
		localparam	AW = (IAW<IBW) ? IAW : IBW,
				BW = (IAW<IBW) ? IBW : IAW,
				IW=(AW+1)&(-2),	// Internal width of A
				LUTB=2,	// How many bits to mpy at once
				TLEN=(AW+(LUTB-1))/LUTB // Rows in our tableau
		// }}}
	) (
		// {{{
		input	logic			i_clk, i_ce,
		input	logic	[(IAW-1):0]	i_a_unsorted,
		input	logic	[(IBW-1):0]	i_b_unsorted,
		output	logic	[(AW+BW-1):0]	o_r

		// }}}
	);
	// Local declarations
	// {{{
	// Swap parameter order, so that AW <= BW -- for performance
	// reasons
	logic	[AW-1:0]	i_a;
	logic	[BW-1:0]	i_b;
	generate begin : PARAM_CHECK
	if (IAW <= IBW)
	begin : NO_PARAM_CHANGE_I
		assign i_a = i_a_unsorted;
		assign i_b = i_b_unsorted;
	end else begin : SWAP_PARAMETERS_I
		assign i_a = i_b_unsorted;
		assign i_b = i_a_unsorted;
	end end endgenerate

	logic	[(IW-1):0]	u_a;
	logic	[(BW-1):0]	u_b;
	logic			sgn;

	logic	[(IW-1-2*(LUTB)):0]	r_a[0:(TLEN-3)];
	logic	[(BW-1):0]		r_b[0:(TLEN-3)];
	logic	[(TLEN-1):0]		r_s;
	logic	[(IW+BW-1):0]		acc[0:(TLEN-2)];
	genvar k;

	logic	[(BW+LUTB-1):0]	pr_a, pr_b;
	logic	[(IW+BW-1):0]	w_r;
	// }}}

	// First step:
	// Switch to unsigned arithmetic for our multiply, keeping track
	// of the along the way.  We'll then add the sign again later at
	// the end.
	//
	// If we were forced to stay within two's complement arithmetic,
	// taking the absolute value here would require an additional bit.
	// However, because our results are now unsigned, we can stay
	// within the number of bits given (for now).

	// u_a
	// {{{
	initial u_a = 0;
	generate begin : ABS
	if (IW > AW)
	begin : ABS_AND_ADD_BIT_TO_A
		always @(posedge i_clk)
		if (i_ce)
			u_a <= { 1'b0, (i_a[AW-1])?(-i_a):(i_a) };
	end else begin : ABS_A
		always @(posedge i_clk)
		if (i_ce)
			u_a <= (i_a[AW-1])?(-i_a):(i_a);
	end end endgenerate
	// }}}

	// sgn, u_b
	// {{{
	initial sgn = 0;
	initial u_b = 0;
	always @(posedge i_clk)
	if (i_ce)
	begin : ABS_B
		u_b <= (i_b[BW-1])?(-i_b):(i_b);
		sgn <= i_a[AW-1] ^ i_b[BW-1];
	end
	// }}}

	//
	// Second step: First two 2xN products.
	//
	// Since we have no tableau of additions (yet), we can do both
	// of the first two rows at the same time and add them together.
	// For the next round, we'll then have a previous sum to accumulate
	// with new and subsequent product, and so only do one product at
	// a time can follow this--but the first clock can do two at a time.
	bimpy	#(
		.BW(BW)
	) lmpy_0(
		// {{{
		.i_clk(i_clk),.i_reset(1'b0),.i_ce(i_ce),
		.i_a(u_a[(  LUTB-1):   0]),
		.i_b(u_b),
		.o_r(pr_a)
		// }}}
	);
	bimpy	#(
		.BW(BW)
	) lmpy_1(
		// {{{
		.i_clk(i_clk),.i_reset(1'b0),.i_ce(i_ce),
		.i_a(u_a[(2*LUTB-1):LUTB]),
		.i_b(u_b),
		.o_r(pr_b)
		// }}}
	);

	// r_s, r_a[0], r_b[0]
	// {{{
	initial r_s    = 0;
	initial r_a[0] = 0;
	initial r_b[0] = 0;
	always @(posedge i_clk)
	if (i_ce)
	begin
		r_a[0] <= u_a[(IW-1):(2*LUTB)];
		r_b[0] <= u_b;
		r_s <= { r_s[(TLEN-2):0], sgn };
	end
	// }}}

	// acc[0]
	// {{{
	initial acc[0] = 0;
	always @(posedge i_clk) // One clk after p[0],p[1] become valid
	if (i_ce)
		acc[0] <= { {(IW-LUTB){1'b0}}, pr_a}
		  +{ {(IW-(2*LUTB)){1'b0}}, pr_b, {(LUTB){1'b0}} };
	// }}}

	// r_a[TLEN-3:1], r_b[TLEN-3:1]
	// {{{
	generate begin : COPY
	// Keep track of intermediate values, before multiplying them
	if (TLEN > 3) begin : FOR
	for(k=0; k<TLEN-3; k=k+1)
	begin : GENCOPIES

		initial r_a[k+1] = 0;
		initial r_b[k+1] = 0;
		always @(posedge i_clk)
		if (i_ce)
		begin
			r_a[k+1] <= { {(LUTB){1'b0}},
				r_a[k][(IW-1-(2*LUTB)):LUTB] };
			r_b[k+1] <= r_b[k];
		end
	end end end endgenerate
	// }}}

	// acc[TLEN-2:1]
	// {{{
	generate begin : STAGES
	// The actual multiply and accumulate stage
	if (TLEN > 2) begin : FOR
	for(k=0; k<TLEN-2; k=k+1)
	begin : GENSTAGES
		logic	[(BW+LUTB-1):0] genp;

		// First, the multiply: 2-bits times BW bits
		bimpy #(
			.BW(BW)
		) genmpy(
			// {{{
			.i_clk(i_clk),.i_reset(1'b0),.i_ce(i_ce),
			.i_a(r_a[k][(LUTB-1):0]),
			.i_b(r_b[k]),
			.o_r(genp)
			// }}}
		);

		// Then the accumulate step -- on the next clock
		initial acc[k+1] = 0;
		always @(posedge i_clk)
		if (i_ce)
			acc[k+1] <= acc[k] + {{(IW-LUTB*(k+3)){1'b0}},
				genp, {(LUTB*(k+2)){1'b0}} };
	end end end endgenerate
	// }}}

	assign	w_r = (r_s[TLEN-1]) ? (-acc[TLEN-2]) : acc[TLEN-2];

	// o_r
	// {{{
	initial o_r = 0;
	always @(posedge i_clk)
	if (i_ce)
		o_r <= w_r[(AW+BW-1):0];
	// }}}

	// Make Verilator happy
	// {{{
	generate begin : GUNUSED
	if (IW > AW)
	begin : VUNUSED
		// verilator lint_off UNUSED
		logic	unused;
		assign	unused = &{ 1'b0, w_r[(IW+BW-1):(AW+BW)] };
		// verilator lint_on UNUSED
	end end endgenerate
	// }}}

endmodule
