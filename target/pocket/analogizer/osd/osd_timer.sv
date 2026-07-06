// Project: OSD Overlay
// File: osd_timer.sv
// Description: Overlay module for displaying OSD (On-Screen Display) characters
//              on a VGA screen. It uses a character RAM and a font ROM to
//              generate the pixel data for the OSD characters.
// Author: @RndMnkIII
// Date: 2025-05-09
// License: MIT
//
`default_nettype none
module osd_timer #(
    parameter int CLK_HZ = 32_000_000,
    parameter int DURATION_SEC = 3 // duración en segundos (1 a 5 típicamente)
)(
    input  logic clk,
    input  logic reset,
    input  logic enable,       // reinicia temporizador si se activa
    output logic active        // en alto mientras el temporizador no ha expirado
);

    localparam int MAX_COUNT = CLK_HZ * DURATION_SEC;

    logic [$clog2(MAX_COUNT)-1:0] counter = 0;

    always_ff @(posedge clk) begin
        if (reset) begin
            counter <= 0;
            active  <= 1'b0;
        end else if (enable) begin
            counter <= MAX_COUNT - 1;
            active  <= 1'b1;
        end else if (active) begin
            if (counter != 0)
                counter <= counter - 1;
            else
                active <= 1'b0;
        end
    end

endmodule
