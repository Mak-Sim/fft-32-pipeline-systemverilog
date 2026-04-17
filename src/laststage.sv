////////////////////////////////////////////////////////////////////////////////
//
// Filename:	laststage.v
// {{{
// Project:	A General Purpose Pipelined FFT Implementation
//
// Purpose:	This is part of an FPGA implementation that will process
//		the final stage of a decimate-in-frequency FFT, running
//	through the data at one sample per clock.
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
module	laststage #(
		// {{{
		parameter IWIDTH=16,OWIDTH=IWIDTH+1, SHIFT=0
		// }}}
	) (
		// {{{
		input logic			i_clk, i_reset, i_ce, i_sync,
		input logic  [(2*IWIDTH-1):0]	i_val,
		output logic [(2*OWIDTH-1):0]	o_val,
		output logic			o_sync
		// }}}
	);
	
	// -----------------------------------------------------------------------
    // Внутренние сигналы
    // -----------------------------------------------------------------------
    logic signed [(IWIDTH-1):0]  m_r, m_i;          // память: первый отсчёт пары
    logic signed [(IWIDTH-1):0]  i_r, i_i;           // текущий вход (Re и Im)

    // Промежуточные результаты бабочки (IWIDTH+1 бит - рост на 1 из-за сложения)
    logic signed [(IWIDTH):0]    rnd_r, rnd_i;       // выход на convround (сумма или разность)
    logic signed [(IWIDTH):0]    sto_r, sto_i;       // хранение разности до следующего такта

    logic                        wait_for_sync;       // ждём первый i_sync
    logic                        stage;               // 0 = первый такт пары, 1 = второй такт
    logic [1:0]                  sync_pipe;           // задержка sync для выравнивания с o_val
    logic signed [(OWIDTH-1):0]  o_r, o_i;           // финальные выходы (после округления)

    // -----------------------------------------------------------------------
    // Распаковка комплексного входа
    // -----------------------------------------------------------------------
    assign i_r = i_val[(2*IWIDTH-1):(IWIDTH)];
    assign i_i = i_val[(IWIDTH-1):0];

    // -----------------------------------------------------------------------
    // TODO 1: Управление сигналами wait_for_sync и stage
    //
    // Условия:
    //   - После сброса: wait_for_sync=1, stage=0
    //   - При (i_ce && (не ждём синхронизации ИЛИ пришёл i_sync) && stage==0):
    //       * Снять wait_for_sync
    //       * Перевести stage в 1
    //   - В остальных случаях при i_ce:
    //       * Перевести stage обратно в 0
    //
    // -----------------------------------------------------------------------
    initial wait_for_sync = 1'b1;
    initial stage         = 1'b0;
//    always_ff @(posedge i_clk)
//    if (i_reset) begin
//        wait_for_sync <= 1'b1;
//        stage         <= 1'b0;
//    end else if (i_ce) begin
//        // TODO: реализуйте логику переключения stage и wait_for_sync
//        // ...
//    end

    // -----------------------------------------------------------------------
    // TODO 2: Конвейер синхросигнала sync_pipe
    //
    // sync_pipe[0] <- i_sync (на такте i_ce)
    // sync_pipe[1] <- sync_pipe[0]
    // o_sync       <- sync_pipe[1]
    //
    // Это необходимо, потому что между i_sync и первым валидным o_val
    // проходит 2 такта (хранение + вычисление + округление через convround).
    // -----------------------------------------------------------------------
    
//    initial sync_pipe = 0;
//    always_ff @(posedge i_clk)
//    if (i_reset)
//        sync_pipe <= 0;
//    else if (i_ce)
//        sync_pipe <= /* TODO */;

//    initial o_sync = 1'b0;
//    always_ff @(posedge i_clk)
//    if (i_reset)
//        o_sync <= 1'b0;
//    else if (i_ce)
//        o_sync <= /* TODO: какой бит sync_pipe? */;

    // -----------------------------------------------------------------------
    // TODO 3: Логика вычисления бабочки
    //
    // При stage=0 (первый такт пары):
    //   * Сохранить входной отсчёт: m_r <= i_r, m_i <= i_i
    //   * Вывести разность, накопленную на прошлом шаге: rnd_r <= sto_r, rnd_i <= sto_i
    //
    // При stage=1 (второй такт пары):
    //   * Вычислить сумму:     rnd_r <= m_r + i_r,  rnd_i <= m_i + i_i
    //   * Вычислить разность:  sto_r <= m_r - i_r,  sto_i <= m_i - i_i
    //
    // Обратите внимание: rnd_r / rnd_i имеют ширину IWIDTH+1 бит (знаковое расширение).
    // -----------------------------------------------------------------------
//    always_ff @(posedge i_clk)
//    if (i_ce) begin
//        if (!stage) begin
//            // TODO: сохранение и вывод разности
//        end else begin
//            // TODO: вычисление суммы и разности
//        end
//    end

    // -----------------------------------------------------------------------
    // Округление и формирование выхода
    // (эта часть уже реализована - не изменяйте)
    // -----------------------------------------------------------------------
    convround #(IWIDTH+1, OWIDTH, SHIFT) do_rnd_r (i_clk, i_ce, rnd_r, o_r);
    convround #(IWIDTH+1, OWIDTH, SHIFT) do_rnd_i (i_clk, i_ce, rnd_i, o_i);

    assign o_val = { o_r, o_i };

endmodule
