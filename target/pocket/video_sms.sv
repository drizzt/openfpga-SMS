//
// video_sms.sv — raster output adapter for the Analogue Pocket scaler
//
// The SMS VDP is a raster core: video.vhd generates timing (x/y/syncs/blanks)
// in the clk_sys domain, advancing one pixel per ce_pix (clk_sys/10), and
// system.vhd returns the 12-bit color for the current x/y. clk_vid is the
// exact SMS dot clock (5.3693175 MHz = clk_sys/10) from the same PLL VCO,
// so each clk_vid edge samples exactly one pixel — no framebuffer needed.
//
// Active windows produced by video.vhd (border=0):
//   SMS/SG 192-line: 256x192      SMS 224-line (M1&M2): 256x224
//   SMS 240-line (M3&M2): 256x240 GG (ggres=1): 160x144
// PAL needs no handling here: it only changes total/blanking lines
// (313-line frames, ~49.7 Hz), the active windows and therefore the
// scaler slots stay the same — slot selection is mode-register-driven.
//
// The Pocket scaler does NOT measure the DE window: the core must select
// the video.json scaler_modes slot itself, by driving the slot index on
// video_rgb[23:13] (function code 0 = "set scaler slot" on [2:0]) during
// the blanking cycle right after DE falls. An all-zero blanking value
// keeps requesting slot 0, so the slot word below must match the
// scaler_modes order: 0=256x192, 1=256x224, 2=256x240, 3=160x144.
//

`default_nettype none

module video_sms (
    input wire        clk_sys,
    input wire        clk_vid,    // = clk_sys/10, phase-locked (same PLL)
    input wire        reset,

    // From SMS core (clk_sys domain, stable for 10 clk_sys per pixel)
    input wire [11:0] color,      // {B[3:0], G[3:0], R[3:0]}
    input wire        hs,
    input wire        vs,
    input wire        hblank,
    input wire        vblank,

    // Current video mode (clk_sys domain, quasi-static)
    input wire        ggres,
    input wire        smode_M1,
    input wire        smode_M2,
    input wire        smode_M3,

    // To Pocket scaler (clk_vid domain)
    output reg [23:0] video_rgb,
    output reg        video_de,
    output reg        video_hs,
    output reg        video_vs,
    output wire       video_skip
);

    // Every clk_vid cycle is a pixel — never skip
    assign video_skip = 1'b0;

    // Re-register in clk_sys first so the cross-domain path is reg->reg
    reg [11:0] color_r;
    reg        hs_r, vs_r, hbl_r, vbl_r;
    reg [2:0]  slot_r;
    always @(posedge clk_sys) begin
        color_r <= color;
        hs_r    <= hs;
        vs_r    <= vs;
        hbl_r   <= hblank;
        vbl_r   <= vblank;
        slot_r  <= ggres                  ? 3'd3 :
                   (smode_M1 & smode_M2)  ? 3'd1 :
                   (smode_M3 & smode_M2)  ? 3'd2 : 3'd0;
    end

    // SMS color: 4 bits per channel, replicate nibble to 8 bits
    // (same expansion as MiSTer SMS.sv video_mixer wiring)
    wire [7:0] r8 = {2{color_r[3:0]}};
    wire [7:0] g8 = {2{color_r[7:4]}};
    wire [7:0] b8 = {2{color_r[11:8]}};

    reg hs_d, vs_d;
    always @(posedge clk_vid) begin
        if (reset) begin
            video_rgb <= 24'd0;
            video_de  <= 1'b0;
            video_hs  <= 1'b0;
            video_vs  <= 1'b0;
            hs_d      <= 1'b0;
            vs_d      <= 1'b0;
        end else begin
            hs_d <= hs_r;
            vs_d <= vs_r;

            video_de <= ~(hbl_r | vbl_r);
            if (~(hbl_r | vbl_r))
                video_rgb <= {r8, g8, b8};
            else if (video_de)
                // first blanking cycle after DE falls: scaler slot select
                video_rgb <= {8'd0, slot_r, 13'd0};
            else
                video_rgb <= 24'd0;

            // Rising edge -> single clk_vid pulse
            video_hs <= hs_r & ~hs_d;
            video_vs <= vs_r & ~vs_d;
        end
    end

endmodule
