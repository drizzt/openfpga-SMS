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
module osd_overlay #(
    parameter int CHAR_WIDTH  = 8,
    parameter int CHAR_HEIGHT = 8,
    parameter int SCREEN_COLS = 48,
    parameter int SCREEN_ROWS = 32
)(
    input  logic        clk,           // Reloj maestro 32 MHz
    input  logic        reset,
    input  logic        hblank,        // HBlank activo durante el blanking
    input  logic        vblank,        // VBlank activo durante el blanking
    input  logic  [9:0] x,             // Coordenada X del píxel actual
    input  logic  [9:0] y,             // Coordenada Y del píxel actual
    input  logic        osd_active,    // Activo mientras el temporizador esté contando
    output logic [10:0] addr_b,
    input  logic [7:0] char_code,
    output logic [2:0]  video_out,      // Salida RGB modificada
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
    assign char_col = x[9:3]; // x / 8
    assign char_row = y[9:3]; // y / 8

    //adds one clock cycle delay to the RAM address
    always_ff @(posedge clk) begin
        addr_b <= char_row * SCREEN_COLS + char_col;
    end
    //assign addr_b = {char_row, char_col}; // Direccion de la ram de texto

    //en el siguiente ciclo de reloj obtenemos el dato en char_code

    //se añaden etapas de pipeline para evitar retrasos entre señales
    logic [2:0] y20_r, y20_r2;
    logic [2:0] X20_r, x20_r2;
    always_ff @(posedge clk) begin
        y20_r <= y[2:0]; // Guardamos el valor de y[2:0] para usarlo en la rom
        y20_r2 <= y20_r;
        X20_r <= x[2:0]; // Guardamos el valor de x[2:0] para usarlo en la rom
    end

    //obtener direccion de la rom
    //caracter + posicion y
    logic [10:0] font_addr;
    assign font_addr = {char_code, y20_r2}; // Direccion de la rom de fuente

    // Acceso a ROM de fuente
    logic [7:0]  font_data;
    osd_font_rom font_inst (
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

    logic display_bit;
    always_ff @(posedge clk) begin
        //display_bit <= font_data[X20_r3]; // Extraer el bit correspondiente al pixel (Reversed)
        display_bit <= font_data[7-X20_r3]; // Extraer el bit correspondiente al pixel
    end

    assign video_out = (dar4 && osdar4) ? {3{display_bit}} : 3'b000; // Si estamos en la zona activa y el OSD está activo, mostramos el bit de OSD
endmodule