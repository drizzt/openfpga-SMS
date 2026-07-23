// Project: OSD Overlay
// File:  osd_overlay.sv
// Description: Overlay module for displaying OSD (On-Screen Display) characters
//              on a VGA screen. It uses a character RAM and a font ROM to
//              generate the pixel data for the OSD characters.
// Author: @RndMnkIII
// Date: 2025-05-09
// License: MIT
//
`default_nettype none
module char_ram_dualport #(
    parameter int ADDR_WIDTH = 11,                      // 2^11 = 2048 posiciones
    parameter int DATA_WIDTH = 8,                       // Cada carácter = 8 bits ASCII
    parameter int DEPTH = 1 << ADDR_WIDTH,              // Profundidad real de la RAM
    parameter INIT_FILE = "char_ram.mem"     // Archivo de inicialización
)(
    input  logic                  clk,

    // Puerto A: escritura (desde osd_top)
    input  logic                  we_a,
    input  logic [ADDR_WIDTH-1:0] addr_a,
    input  logic [DATA_WIDTH-1:0] data_a,

    // Puerto B: lectura (desde osd_overlay)
    input  logic [ADDR_WIDTH-1:0] addr_b,
    output logic [DATA_WIDTH-1:0] data_b
);

    // Memoria
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Inicialización desde fichero externo
    initial $readmemh(INIT_FILE, mem);

    // Escritura por puerto A
    always_ff @(posedge clk) begin
        if (we_a)
            mem[addr_a] <= data_a;

        // Lectura por puerto B (siempre activa)
        data_b <= mem[addr_b];
    end

endmodule
