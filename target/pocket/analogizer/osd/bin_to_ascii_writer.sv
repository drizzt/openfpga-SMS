// Project: OSD Overlay
// File: bin_to_ascii_writer.sv
// Description: Overlay module for displaying OSD (On-Screen Display) characters
//              on a VGA screen. It uses a character RAM and a font ROM to
//              generate the pixel data for the OSD characters.
// Author: @RndMnkIII
// Date: 2025-05-10
// License: MIT
//
`default_nettype none

module bin_to_ascii_writer #(
    parameter bit SHOW_SIGN = 1  // Mostrar '+' o '-' como prefijo
)(
    input  logic        clk,
    input  logic        start,
    input  logic signed [13:0] value,
    input  logic [10:0] base_addr,
    output logic        wr_en,
    output logic [10:0] wr_addr,
    output logic [7:0]  wr_data,
    output logic        busy
);

    typedef enum logic [2:0] {
        IDLE,
        CONVERT,
        WRITE_SIGN,
        WRITE_DIGIT_0,
        WRITE_DIGIT_1,
        WRITE_DIGIT_2,
        WRITE_DIGIT_3,
        DONE
    } state_t;

    state_t state;

    logic [13:0] abs_value;
    logic [15:0] bcd_digits;
    logic [3:0] digit;
    logic [7:0] ascii_digit;
    logic bcd_done, bcd_start;
    logic [2:0] digit_index;
    logic [10:0] addr_base_r;

    assign digit = bcd_digits[15 - digit_index*4 -: 4];
    assign ascii_digit = 8'h30 + digit;

    Binary_to_BCD #(
        .INPUT_WIDTH(14),
        .DECIMAL_DIGITS(4)
    ) bcd_inst (
        .i_Clock(clk),
        .i_Binary(abs_value),
        .i_Start(bcd_start),
        .o_BCD(bcd_digits),
        .o_DV(bcd_done)
    );

    always_ff @(posedge clk) begin
        wr_en <= 0;

        case (state)
            IDLE: begin
                if (start) begin
                    abs_value   <= (value < 0) ? -value : value;
                    addr_base_r <= base_addr;
                    bcd_start   <= 1;
                    state       <= CONVERT;
                end
            end

            CONVERT: begin
                bcd_start <= 0;
                if (bcd_done) begin
                    if (SHOW_SIGN) begin
                        wr_addr <= addr_base_r;
                        wr_data <= (value < 0) ? 8'h2D : 8'h2B;
                        wr_en   <= 1;
                        digit_index <= 0;
                        state <= WRITE_SIGN;
                    end else begin
                        digit_index <= 0;
                        state <= WRITE_DIGIT_0;
                    end
                end
            end

            WRITE_SIGN: begin
                wr_en   <= 0;
                state   <= WRITE_DIGIT_0;
            end

            WRITE_DIGIT_0: begin
                wr_addr <= addr_base_r + (SHOW_SIGN ? 1 : 0);
                wr_data <= ascii_digit;
                wr_en   <= 1;
                digit_index <= 1;
                state <= WRITE_DIGIT_1;
            end

            WRITE_DIGIT_1: begin
                wr_addr <= addr_base_r + (SHOW_SIGN ? 2 : 1);
                wr_data <= ascii_digit;
                wr_en   <= 1;
                digit_index <= 2;
                state <= WRITE_DIGIT_2;
            end

            WRITE_DIGIT_2: begin
                wr_addr <= addr_base_r + (SHOW_SIGN ? 3 : 2);
                wr_data <= ascii_digit;
                wr_en   <= 1;
                digit_index <= 3;
                state <= WRITE_DIGIT_3;
            end

            WRITE_DIGIT_3: begin
                wr_addr <= addr_base_r + (SHOW_SIGN ? 4 : 3);
                wr_data <= ascii_digit;
                wr_en   <= 1;
                state <= DONE;
            end

            DONE: begin
                wr_en <= 0;
                state <= IDLE;
            end
        endcase
    end

    assign busy = (state != IDLE);

endmodule