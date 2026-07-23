`default_nettype none
module osd_font_rom (
    input  logic        clk,
    input  logic [10:0] addr,   // 256 chars * 8 lines = 2048 = 11 bits
    output logic [7:0]  data
);
    logic [7:0] rom [0:2047];

    initial begin
        $readmemh("font_gfx1.mem", rom);
    end

    always_ff @(posedge clk) begin
        data <= rom[addr];
    end
endmodule
