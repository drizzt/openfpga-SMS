//------------------------------------------------------------------------------
// SPDX-License-Identifier: MIT
// SPDX-FileType: SOURCE
// SPDX-FileCopyrightText: (c) 2023, OpenGateware authors and contributors
//------------------------------------------------------------------------------
//
// Analogue Pocket Audio Mixer
//
// Copyright (c) 2023, Marcus Andrade <marcus@opengateware.org>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
//------------------------------------------------------------------------------

`default_nettype none

module audio_mixer #(
    parameter DW     = 16,  //! Audio Data Width
    parameter STEREO = 1    //! Stereo Audio
) (
    // Clocks and Reset
    input  logic          clk_74b,     //! Clock 74.25Mhz
    input  logic          clk_audio,
    input  logic          reset,       //! Reset
    // Controls
    input  logic [   3:0] vol_att,     //! Volume ([0] Max | [7] Min)
    input  logic [   1:0] mix,         //! [0] No Mix | [1] 25% | [2] 50% | [3] 100% (mono)
    // Audio From Core
    input  logic          is_signed,   //! Signed Audio
    input  logic [DW-1:0] core_l,      //! Left  Channel Audio from Core
    input  logic [DW-1:0] core_r,      //! Right Channel Audio from Core
    // Pocket I2S
    output logic          audio_mclk,  //! Serial Master Clock
    output logic          audio_lrck,  //! Left/Right clock
    output logic          audio_dac    //! Serialized data
);

  //! ------------------------------------------------------------------------
  //! Audio Clocks
  //! MCLK: 12.288MHz (256*Fs, where Fs = 48000)
  //! SCLK:  3.072mhz (MCLK/4)
  //! ------------------------------------------------------------------------
  wire audio_sclk;

  mf_audio_pll audio_pll (
      .refclk  (clk_74b),
      .rst     (0),
      .outclk_0(audio_mclk),
      .outclk_1(audio_sclk)
  );

  //! ------------------------------------------------------------------------
  //! Pad core_l/core_r with zeros to maintain a consistent size of 16 bits
  //! ------------------------------------------------------------------------
  logic [15:0] core_al, core_ar;

  always_comb begin
    core_al = DW == 16 ? core_l : {core_l, {16 - DW{1'b0}}};
    core_ar = STEREO ? DW == 16 ? core_r : {core_r, {16 - DW{1'b0}}} : core_al;
  end

  //! ------------------------------------------------------------------------
  //! Synchronization
  //! clk_audio -> audio_mclk. Both channels cross as one 32-bit entry so the
  //! two can never come from different samples, pushed only when the core
  //! output changed. audio_filters' own 2-cycle stability compare is left in
  //! place but no longer carries the crossing on its own.
  //! ------------------------------------------------------------------------
  logic [15:0] core_al_s, core_ar_s;

  reg write_en = 0;
  reg [15:0] prev_left;
  reg [15:0] prev_right;

  sync_fifo #(
      .WIDTH(32)
  ) sync_fifo (
      .clk_write(clk_audio),
      .clk_read (audio_mclk),

      .write_en(write_en),
      .data    ({core_al, core_ar}),
      .data_s  ({core_al_s, core_ar_s})
  );

  always @(posedge clk_audio) begin
    prev_left  <= core_al;
    prev_right <= core_ar;

    write_en   <= 0;

    if (core_al != prev_left || core_ar != prev_right) begin
      write_en <= 1;
    end
  end

  //! ------------------------------------------------------------------------
  //! Audio Output
  //! IIR low-pass filter removed to conserve ALMs: the Pocket's DAC has
  //! built-in oversampling/interpolation. DC blocker and mix retained.
  //! ------------------------------------------------------------------------
  wire [15:0] audio_l, audio_r;

  audio_filters audio_filters (
      .clk  (audio_mclk),
      .reset(reset),

      .att({1'b0, vol_att}),

      .is_signed(is_signed),
      .mix      (mix),

      .core_l(core_al_s),
      .core_r(core_ar_s),

      .audio_l(audio_l),
      .audio_r(audio_r)
  );

  //! ------------------------------------------------------------------------
  //! Pocket I2S Output
  //! ------------------------------------------------------------------------

  sound_i2s sound_i2s (
      .audio_sclk(audio_sclk),

      .audio_l(audio_l),
      .audio_r(audio_r),

      .audio_lrck(audio_lrck),
      .audio_dac (audio_dac)
  );

endmodule
