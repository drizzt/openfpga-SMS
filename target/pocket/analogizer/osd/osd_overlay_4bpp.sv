// Project: OSD Overlay
// File: osd_overlay.sv
// Description: Overlay module for displaying OSD (On-Screen Display) characters
//              on a VGA screen. It uses a character RAM and a font ROM to
//              generate the pixel data for the OSD characters.
// Author: @RndMnkIII
// Date: 2025-05-10
// License: MIT
//
`default_nettype none
module osd_overlay_4bpp #(
    parameter int CHAR_WIDTH  = 8,
    parameter int CHAR_HEIGHT = 8,
    parameter int SCREEN_COLS = 32,
    parameter int SCREEN_ROWS = 32
)(
    input  logic        rot90,
    input  logic        clk,           // Reloj maestro 32 MHz
    input  logic        reset,
    input  logic        hblank,        // HBlank activo durante el blanking
    input  logic        vblank,        // VBlank activo durante el blanking
    input  logic  [9:0] x,             // Coordenada X del píxel actual
    input  logic  [9:0] y,             // Coordenada Y del píxel actual
    input  logic        osd_active,    // Activo mientras el temporizador esté contando
    output logic [10:0] addr_b,
    input  logic [7:0] char_code,
    output logic [24:0]  video_out,      // Salida bit transparente+RGB modificada
    output logic disp_dbg
);
    // Señal para saber si estamos en zona visible
    logic display_active;
    assign display_active = ~hblank & ~vblank;

    // Se añaden registros para evitar delays entre señales de control
    logic dar, dar2, dar3, dar4;
    logic osdar, osdar2, osdar3, osdar4;
    always_ff @(posedge clk) begin
        dar <= display_active;
        dar2 <= dar;
        dar3 <= dar2;
        dar4 <= dar3;
        osdar <= osd_active;
        osdar2 <= osdar;
        osdar3 <= osdar2;
        osdar4 <= osdar3;
    end

    //Calcular direccion ram de donde leer
    logic [5:0] char_col, char_row;
    assign char_col = x[8:3]; // x / 8 //char_col 6
    assign char_row = y[8:3]; // y / 8

    //adds one clock cycle delay to the RAM address
    always_ff @(posedge clk) begin
        addr_b <= char_row * SCREEN_COLS + char_col; //addr_b 11
    end

    //en el siguiente ciclo de reloj obtenemos el dato en char_code

    //se añaden etapas de pipeline para evitar retrasos entre señales
    logic [2:0] y20_r, y20_r2;
    logic [2:0] X20_r, x20_r2;

    always_ff @(posedge clk) begin
        y20_r <= y[2:0]; // Guardamos el valor de y[2:0] para usarlo en la rom
        y20_r2 <= y20_r;
        X20_r <= x[2:0]; // Guardamos el valor de x[2:0] para usarlo en la rom
    end
    // always_ff @(posedge clk) begin
    //     if (rot90) begin
    //         y20_r <= x[2:0]; // Guardamos el valor de x[2:0] para usarlo en la rom
    //         y20_r2 <= y20_r;
    //         X20_r <= y[2:0]; // Guardamos el valor de y[2:0] para usarlo en la rom
    //     end else begin
    //         y20_r <= y[2:0]; // Guardamos el valor de y[2:0] para usarlo en la rom
    //         y20_r2 <= y20_r;
    //         X20_r <= x[2:0]; // Guardamos el valor de x[2:0] para usarlo en la rom
    //     end
    // end

    //obtener direccion de la rom
    //caracter + posicion y
    logic [10:0] font_addr;
    assign font_addr = {char_code, y20_r2}; // Direccion de la rom de fuente

    // Acceso a ROM de fuente
    logic [31:0]  font_data;
    osd_font_rom_4bpp #(.FONT_MEM_FILE("font_graffitti.mem")) font_inst (
        .clk(clk),
        .addr(font_addr),
        .data(font_data)
    );
    //en el siguiente ciclo de reloj obtenemos el dato en ROM
    logic [2:0] X20_rr, X20_r3;
    //extraer bits de columna del dato ROM
    always_ff @(posedge clk) begin
        X20_rr <= X20_r;
        X20_r3 <= X20_rr;
    end

    logic [3:0] color_index;

	logic [23:0] color_out;

    always_comb begin
        case (X20_r3)
            3'd7: color_index = font_data[3:0];   // extrae indice de color del pixel 7
            3'd6: color_index = font_data[7:4];   // extrae indice de color del pixel 6
            3'd5: color_index = font_data[11:8];  // extrae indice de color del pixel 5
            3'd4: color_index = font_data[15:12]; // extrae indice de color del pixel 4
            3'd3: color_index = font_data[19:16]; // extrae indice de color del pixel 3
            3'd2: color_index = font_data[23:20]; // extrae indice de color del pixel 2
            3'd1: color_index = font_data[27:24]; // extrae indice de color del pixel 1
            3'd0: color_index = font_data[31:28]; // extrae indice de color del pixel 0
        endcase
    end

    logic trans_col;
    always_ff @(posedge clk) begin
        trans_col <= 1'b1;
        if ((color_index < 4'hf) && dar4 && osdar4) trans_col <= 1'b0; // 15 indice transparente de la paleta
    end

	osd_font_color_pal #(.PAL_MEM_FILE("graffitti_pal.mem")) col_pal(
    .clk(clk),
    .addr(color_index),
    .R(color_out[23:16]), .G(color_out[15:8]), .B(color_out[7:0]));

    assign video_out = {trans_col, color_out};
endmodule