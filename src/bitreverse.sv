////////////////////////////////////////////////////////////////////////////////
//
// Filename:	bitreverse.v
// {{{
// Project:	A General Purpose Pipelined FFT Implementation
//
// Purpose:	This module bitreverses a pipelined FFT input.  It differes
//		from the dblreverse module in that this is just a simple and
//	straightforward bitreverse, rather than one written to handle two
//	words at once.
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
`default_nettype	none
//
module	bitreverse #(
		// {{{
		parameter			LGSIZE=5, WIDTH=24
		// }}}
	) (
		// {{{
		input logic			i_clk, i_reset, i_ce,
		input logic	[(2*WIDTH-1):0]	i_in,
		output logic	[(2*WIDTH-1):0]	o_out,
		output logic			o_sync
		// }}}
	);

	// Local declarations
	// {{{
	logic	[(LGSIZE):0]	wraddr;
	logic	[(LGSIZE):0]	rdaddr;

	logic	[(2*WIDTH-1):0]	brmem	[0:((1<<(LGSIZE+1))-1)];

	logic	in_reset;
	// }}}

	// bitreverse rdaddr
	// {{{
	genvar	k;
	generate for(k=0; k<LGSIZE; k=k+1)
	begin : DBL
		assign rdaddr[k] = wraddr[LGSIZE-1-k];
	end endgenerate
	assign	rdaddr[LGSIZE] = !wraddr[LGSIZE];
	// }}}

	// in_reset
	// {{{
	initial	in_reset = 1'b1;
	always_ff @(posedge i_clk)
	if (i_reset)
		in_reset <= 1'b1;
	else if ((i_ce)&&(&wraddr[(LGSIZE-1):0]))
		in_reset <= 1'b0;
	// }}}

	// wraddr
	// {{{
	initial	wraddr = 0;
	always_ff @(posedge i_clk)
	if (i_reset)
		wraddr <= 0;
	else if (i_ce)
	begin
		brmem[wraddr] <= i_in;
		wraddr <= wraddr + 1;
	end
	// }}}

	// o_out
	// {{{
	always_ff @(posedge i_clk)
	if (i_ce) // If (i_reset) we just output junk ... not a problem
		o_out <= brmem[rdaddr]; // w/o a sync pulse
	// }}}

	// o_sync
	// {{{
	initial o_sync = 1'b0;
	always_ff @(posedge i_clk)
	if (i_reset)
		o_sync <= 1'b0;
	else if ((i_ce)&&(!in_reset))
		o_sync <= (wraddr[(LGSIZE-1):0] == 0);
	// }}}

endmodule
