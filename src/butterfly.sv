////////////////////////////////////////////////////////////////////////////////
//
// Filename:	butterfly.v
// {{{
// Project:	A General Purpose Pipelined FFT Implementation
//
// Purpose:	This routine caculates a butterfly for a decimation
//		in frequency version of an FFT.  Specifically, given
//	complex Left and Right values together with a coefficient, the output
//	of this routine is given by:
//
//		L' = L + R
//		R' = (L - R)*C
//
//	The rest of the junk below handles timing (mostly), to make certain
//	that L' and R' reach the output at the same clock.  Further, just to
//	make certain that is the case, an 'aux' input exists.  This aux value
//	will come out of this routine synchronized to the values it came in
//	with.  (i.e., both L', R', and aux all have the same delay.)  Hence,
//	a caller of this routine may set aux on the first input with valid
//	data, and then wait to see aux set on the output to know when to find
//	the first output with valid data.
//
//	All bits are preserved until the very last clock, where any more bits
//	than OWIDTH will be quietly discarded.
//
//	This design features no overflow checking.
//
// Notes:
//	CORDIC:
//		Much as we might like, we can't use a cordic here.
//		The goal is to accomplish an FFT, as defined, and a
//		CORDIC places a scale factor onto the data.  Removing
//		the scale factor would cost two multiplies, which
//		is precisely what we are trying to avoid.
//
//
//	3-MULTIPLIES:
//		It should also be possible to do this with three multiplies
//		and an extra two addition cycles.
//
//		We want
//			R+I = (a + jb) * (c + jd)
//			R+I = (ac-bd) + j(ad+bc)
//		We multiply
//			P1 = ac
//			P2 = bd
//			P3 = (a+b)(c+d)
//		Then
//			R+I=(P1-P2)+j(P3-P2-P1)
//
//		WIDTHS:
//		On multiplying an X width number by an
//		Y width number, X>Y, the result should be (X+Y)
//		bits, right?
//		-2^(X-1) <= a <= 2^(X-1) - 1
//		-2^(Y-1) <= b <= 2^(Y-1) - 1
//		(2^(Y-1)-1)*(-2^(X-1)) <= ab <= 2^(X-1)2^(Y-1)
//		-2^(X+Y-2)+2^(X-1) <= ab <= 2^(X+Y-2) <= 2^(X+Y-1) - 1
//		-2^(X+Y-1) <= ab <= 2^(X+Y-1)-1
//		YUP!  But just barely.  Do this and you'll really want
//		to drop a bit, although you will risk overflow in so
//		doing.
//
//	20150602 -- The sync logic lines have been completely redone.  The
//		synchronization lines no longer go through the FIFO with the
//		left hand sum, but are kept out of memory.  This allows the
//		butterfly to use more optimal memory resources, while also
//		guaranteeing that the sync lines can be properly reset upon
//		any reset signal.
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
module	butterfly #(
		// {{{
		// Public changeable parameters ...
		// IWIDTH
		// {{{
		// This is the input data width
		parameter IWIDTH=16,
		// }}}
		// CWIDTH
		// {{{
		// This is the width of the twiddle factor, the 'coefficient'
		// if you will.
		CWIDTH=20,		// }}}
		// OWIDTH
		// {{{
		// This is the width of the final output
		OWIDTH=17,
		// }}}
		// SHIFT
		// {{{
		// The shift controls whether or not the result will be
		// left shifted by SHIFT bits, throwing the overflow
		// away.
		parameter	SHIFT=0,
		// }}}
		// CKPCE
		// {{{
		// CKPCE is the number of clocks per each i_ce.  The actual
		// number can be more, but the algorithm depends upon at least
		// this many for extra internal processing.
		parameter	CKPCE=1,
		// }}}
		//
		// Local/derived parameters
		// {{{
		// These are calculated from the above params.  Apart from
		// algorithmic changes below, these should not be adjusted
		//
		// MXMPYBITS
		// {{{
		// The first step is to calculate how many clocks it takes
		// our multiply to come back with an answer within.  The
		// time in the multiply depends upon the input value with
		// the fewest number of bits--to keep the pipeline depth
		// short.  So, let's find the fewest number of bits here.
		localparam MXMPYBITS =
		((IWIDTH+2)>(CWIDTH+1)) ? (CWIDTH+1) : (IWIDTH + 2),
		// }}}
		// MPYDELAY
		// {{{
		// Given this "fewest" number of bits, we can calculate
		// the number of clocks the multiply itself will take.
		localparam	MPYDELAY=((MXMPYBITS+1)/2)+2,
		// }}}
		// LCLDELAY
		// {{{
		//
		// In an environment when CKPCE > 1, the multiply delay isn't
		// necessarily the delay felt by this algorithm--measured in
		// i_ce's.  In particular, if the multiply can operate with more
		// operations per clock, it can appear to finish "faster".
		// Since most of the logic in this core operates on the
		// slower clock, we'll need to map that speed into the
		// number of slower clock ticks that it takes.
		localparam	LCLDELAY = (CKPCE == 1) ? MPYDELAY
			: (CKPCE == 2) ? (MPYDELAY/2+2)
			: (MPYDELAY/3 + 2),
		// }}}
		// LGDELAY
		// {{{
		localparam	LGDELAY = (MPYDELAY>64) ? 7
			: (MPYDELAY > 32) ? 6
			: (MPYDELAY > 16) ? 5
			: (MPYDELAY >  8) ? 4
			: (MPYDELAY >  4) ? 3
			: 2,
		// }}}
		localparam	AUXLEN=(LCLDELAY+3),
		localparam	MPYREMAINDER = MPYDELAY - CKPCE*(MPYDELAY/CKPCE)
		// }}}
		// }}}
	) (
		// {{{
		input logic	i_clk, i_reset, i_ce,
		input logic	[(2*CWIDTH-1):0] i_coef,
		input logic	[(2*IWIDTH-1):0] i_left, i_right,
		input logic	i_aux,
		output logic	[(2*OWIDTH-1):0] o_left, o_right,
		output logic	o_aux
		// }}}
	);

	// Local delcarations

	logic	[(2*IWIDTH-1):0]	r_left, r_right;
	logic	[(2*CWIDTH-1):0]	r_coef, r_coef_2;
	logic	signed	[(IWIDTH-1):0]	r_left_r, r_left_i, r_right_r, r_right_i;
	logic	signed	[(IWIDTH):0]	r_sum_r, r_sum_i, r_dif_r, r_dif_i;

	logic	[(LGDELAY-1):0]	fifo_addr;
	logic	[(LGDELAY-1):0]	fifo_read_addr;
	logic	[(2*IWIDTH+1):0]	fifo_left [ 0:((1<<LGDELAY)-1)];
	logic	signed	[(CWIDTH-1):0]	ir_coef_r, ir_coef_i;
	logic	signed	[((IWIDTH+2)+(CWIDTH+1)-1):0]	p_one, p_two, p_three;
	logic	signed	[(IWIDTH+CWIDTH):0]	fifo_i, fifo_r;

	logic		[(2*IWIDTH+1):0]	fifo_read;

	logic	signed	[(CWIDTH+IWIDTH+3-1):0]	mpy_r, mpy_i;

	logic	signed	[(OWIDTH-1):0]	rnd_left_r, rnd_left_i, rnd_right_r, rnd_right_i;

	logic	signed	[(CWIDTH+IWIDTH+3-1):0]	left_sr, left_si;
	logic	[(AUXLEN-1):0]	aux_pipeline;
	// }}}

	// Break complex registers into their real and imaginary components
	// {{{
	assign	r_left_r  = r_left[ (2*IWIDTH-1):(IWIDTH)];
	assign	r_left_i  = r_left[ (IWIDTH-1):0];
	assign	r_right_r = r_right[(2*IWIDTH-1):(IWIDTH)];
	assign	r_right_i = r_right[(IWIDTH-1):0];

	assign	ir_coef_r = r_coef_2[(2*CWIDTH-1):CWIDTH];
	assign	ir_coef_i = r_coef_2[(CWIDTH-1):0];
	// }}}

	assign	fifo_read_addr = fifo_addr - LCLDELAY[(LGDELAY-1):0];

	// r_left, r_right, r_coef, r_sum_[r|i], r_dif_[r|i], r_coef_2
	// {{{
	// Set up the input to the multiply
	always_ff @(posedge i_clk)
	if (i_ce)
	begin
		// One clock just latches the inputs
		r_left <= i_left;	// No change in # of bits
		r_right <= i_right;
		r_coef  <= i_coef;
		// Next clock adds/subtracts
		r_sum_r <= r_left_r + r_right_r; // Now IWIDTH+1 bits
		r_sum_i <= r_left_i + r_right_i;
		r_dif_r <= r_left_r - r_right_r;
		r_dif_i <= r_left_i - r_right_i;
		// Other inputs are simply delayed on second clock
		r_coef_2<= r_coef;
	end
	// }}}

	// fifo_addr
	// {{{
	// Don't forget to record the even side, since it doesn't need
	// to be multiplied, but yet we still need the results in sync
	// with the answer when it is ready.
	initial fifo_addr = 0;
	always @(posedge i_clk)
	if (i_reset)
		fifo_addr <= 0;
	else if (i_ce)
		// Need to delay the sum side--nothing else happens
		// to it, but it needs to stay synchronized with the
		// right side.
		fifo_addr <= fifo_addr + 1;
	// }}}

	// Write into the left-side input FIFO
	// {{{
	always_ff @(posedge i_clk)
	if (i_ce)
		fifo_left[fifo_addr] <= { r_sum_r, r_sum_i };
	// }}}

	// Notes
	// {{{
	// Multiply output is always a width of the sum of the widths of
	// the two inputs.  ALWAYS.  This is independent of the number of
	// bits in p_one, p_two, or p_three.  These values needed to
	// accumulate a bit (or two) each.  However, this approach to a
	// three multiply complex multiply cannot increase the total
	// number of bits in our final output.  We'll take care of
	// dropping back down to the proper width, OWIDTH, in our routine
	// below.

	// We accomplish here "Karatsuba" multiplication.  That is,
	// by doing three multiplies we accomplish the work of four.
	// Let's prove to ourselves that this works ... We wish to
	// multiply: (a+jb) * (c+jd), where a+jb is given by
	//	a + jb = r_dif_r + j r_dif_i, and
	//	c + jd = ir_coef_r + j ir_coef_i.
	// We do this by calculating the intermediate products P1, P2,
	// and P3 as
	//	P1 = ac
	//	P2 = bd
	//	P3 = (a + b) * (c + d)
	// and then complete our final answer with
	//	ac - bd = P1 - P2 (this checks)
	//	ad + bc = P3 - P2 - P1
	//	        = (ac + bc + ad + bd) - bd - ac
	//	        = bc + ad (this checks)
	// }}}

	// Instantiate the multiplies
	// {{{
	
		// {{{
		// Local declarations
		// {{{
		logic	[(CWIDTH):0]	p3c_in;
		logic	[(IWIDTH+1):0]	p3d_in;
		// }}}

		assign	p3c_in = ir_coef_i + ir_coef_r;
		assign	p3d_in = r_dif_r + r_dif_i;

		// p_one = ir_coef_r * r_dif_r
		// {{{
		// We need to pad these first two multiplies by an extra
		// bit just to keep them aligned with the third,
		// simpler, multiply.
		longbimpy #(
			.IAW(CWIDTH+1), .IBW(IWIDTH+2)
		) p1(
			// {{{
			.i_clk(i_clk), .i_ce(i_ce),
			.i_a_unsorted({ir_coef_r[CWIDTH-1],ir_coef_r}),
			.i_b_unsorted({r_dif_r[IWIDTH],r_dif_r}),
			.o_r(p_one)
		);

		// p_two = ir_coef_i * r_dif_i
		longbimpy #(
			.IAW(CWIDTH+1), .IBW(IWIDTH+2)
		) p2(
			// {{{
			.i_clk(i_clk), .i_ce(i_ce),
			.i_a_unsorted({ir_coef_i[CWIDTH-1],ir_coef_i}),
			.i_b_unsorted({r_dif_i[IWIDTH],r_dif_i}),
			.o_r(p_two)
		);

		// p_three = (ir_coef_i + ir_coef_r) * (r_dif_r + r_dif_i)
		longbimpy #(
			.IAW(CWIDTH+1), .IBW(IWIDTH+2)
		) p3(
			// {{{
			.i_clk(i_clk), .i_ce(i_ce),
			.i_a_unsorted(p3c_in),
			.i_b_unsorted(p3d_in),
			.o_r(p_three)
		);


	// fifo_r, fifo_i
	// {{{
	// These values are held in memory and delayed during the
	// multiply.  Here, we recover them.  During the multiply,
	// values were multiplied by 2^(CWIDTH-2)*exp{-j*2*pi*...},
	// therefore, the left_x values need to be right shifted by
	// CWIDTH-2 as well.  The additional bits come from a sign
	// extension.
	assign	fifo_r = { {2{fifo_read[2*(IWIDTH+1)-1]}},
		fifo_read[(2*(IWIDTH+1)-1):(IWIDTH+1)], {(CWIDTH-2){1'b0}} };
	assign	fifo_i = { {2{fifo_read[(IWIDTH+1)-1]}},
		fifo_read[((IWIDTH+1)-1):0], {(CWIDTH-2){1'b0}} };
	// }}}

	// Rounding and shifting
	// {{{
	// Notes
	// {{{
	// Let's do some rounding and remove unnecessary bits.
	// We have (IWIDTH+CWIDTH+3) bits here, we need to drop down to
	// OWIDTH, and SHIFT by SHIFT bits in the process.  The trick is
	// that we don't need (IWIDTH+CWIDTH+3) bits.  We've accumulated
	// them, but the actual values will never fill all these bits.
	// In particular, we only need:
	//	 IWIDTH bits for the input
	//	     +1 bit for the add/subtract
	//	+CWIDTH bits for the coefficient multiply
	//	     +1 bit for the add/subtract in the complex multiply
	//	 ------
	//	 (IWIDTH+CWIDTH+2) bits at full precision.
	//
	// However, the coefficient multiply multiplied by a maximum value
	// of 2^(CWIDTH-2).  Thus, we only have
	//	   IWIDTH bits for the input
	//	       +1 bit for the add/subtract
	//	+CWIDTH-2 bits for the coefficient multiply
	//	       +1 (optional) bit for the add/subtract in the cpx mpy.
	//	 -------- ... multiply.  (This last bit may be shifted out.)
	//	 (IWIDTH+CWIDTH) valid output bits.
	// Now, if the user wants to keep any extras of these (via OWIDTH),
	// or if he wishes to arbitrarily shift some of these off (via
	// SHIFT) we accomplish that here.
	// }}}

	assign	left_sr = { {(2){fifo_r[(IWIDTH+CWIDTH)]}}, fifo_r };
	assign	left_si = { {(2){fifo_i[(IWIDTH+CWIDTH)]}}, fifo_i };

	convround #(CWIDTH+IWIDTH+3,OWIDTH,SHIFT+4)
	do_rnd_left_r(i_clk, i_ce, left_sr, rnd_left_r);

	convround #(CWIDTH+IWIDTH+3,OWIDTH,SHIFT+4)
	do_rnd_left_i(i_clk, i_ce, left_si, rnd_left_i);

	convround #(CWIDTH+IWIDTH+3,OWIDTH,SHIFT+4)
	do_rnd_right_r(i_clk, i_ce, mpy_r, rnd_right_r);

	convround #(CWIDTH+IWIDTH+3,OWIDTH,SHIFT+4)
	do_rnd_right_i(i_clk, i_ce, mpy_i, rnd_right_i);
	// }}}

	// fifo_read, mpy_r, mpy_i
	// {{{
	// Unwrap the three multiplies into the two multiply results
	always_ff @(posedge i_clk)
	if (i_ce)
	begin
		// First clock, recover all values
		fifo_read <= fifo_left[fifo_read_addr];
		// These values are IWIDTH+CWIDTH+3 bits wide
		// although they only need to be (IWIDTH+1)
		// + (CWIDTH) bits wide.  (We've got two
		// extra bits we need to get rid of.)
		mpy_r <= p_one - p_two;
		mpy_i <= p_three - p_one - p_two;
	end
	// }}}

	// aux_pipeline
	// {{{
	initial	aux_pipeline = 0;
	always @(posedge i_clk)
	if (i_reset)
		aux_pipeline <= 0;
	else if (i_ce)
		aux_pipeline <= { aux_pipeline[(AUXLEN-2):0], i_aux };
	// }}}

	// o_aux
	// {{{
	initial o_aux = 1'b0;
	always @(posedge i_clk)
	if (i_reset)
		o_aux <= 1'b0;
	else if (i_ce)
	begin
		// Second clock, latch for final clock
		o_aux <= aux_pipeline[AUXLEN-1];
	end
	// }}}

	// o_left, o_right
	// {{{
	// As a final step, we pack our outputs into two packed two's
	// complement numbers per output word, so that each output word
	// has (2*OWIDTH) bits in it, with the top half being the real
	// portion and the bottom half being the imaginary portion.
	assign	o_left = { rnd_left_r, rnd_left_i };
	assign	o_right= { rnd_right_r,rnd_right_i};
	// }}}

endmodule
