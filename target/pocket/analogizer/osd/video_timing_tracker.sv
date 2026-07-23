// Project: OSD Overlay
// File: video_timing_tracker.sv
// Description: Video timing tracker calculates the current pixel position and frame size
// based on horizontal and vertical sync signals.
// Author: @RndMnkIII
// Date: 2025-05-23
// License: MIT
//
`default_nettype none
module video_timing_tracker (
    input  logic clk,
    input  logic pixel_ce,
    input  logic hs,
    input  logic vs,
    input  logic hb,
    input  logic vb,
    output logic [11:0] x,
    output logic [11:0] y,
    output logic [11:0] width,
    output logic [11:0] height,
    output logic ready
);

    logic [11:0] x_pos = 0;
    logic [11:0] y_pos = 0;
    logic [11:0] max_x = 0;
    logic [11:0] max_y = 0;

    logic vs_prev = 0;
    logic pixel_visible = 0;
    logic line_had_visible = 0;

    assign x = x_pos;
    assign y = y_pos;

    always_ff @(posedge clk) begin
        if (pixel_ce) begin
            vs_prev <= vs;

            // detectar inicio de frame
            if (vs_prev == 0 && vs == 1) begin
                width  <= max_x;
                height <= max_y;
                ready  <= 1;
                x_pos  <= 0;
                y_pos  <= 0;
                max_x  <= 0;
                max_y  <= 0;
                line_had_visible <= 0;
            end else begin
                ready <= 0;

                pixel_visible <= (!hb && !vb);

                if (pixel_visible) begin
                    x_pos <= x_pos + 1;
                    if (x_pos > max_x)
                        max_x <= x_pos;

                    line_had_visible <= 1;
                end

                // detectar fin de línea
                if (hs) begin
                    if (line_had_visible) begin
                        y_pos <= y_pos + 1;
                        if (y_pos > max_y)
                            max_y <= y_pos;
                        line_had_visible <= 0;
                    end
                    x_pos <= 0;
                end
            end
        end
    end

endmodule

