`default_nettype none
module osd_font_rom_4bpp (
    input  logic        clk,
    input  logic [10:0] addr,   // 256 chars * 8 lines = 2048 = 11 bits
    output logic [31:0]  data
);

parameter  FONT_MEM_FILE = "";

    logic [31:0] rom [0:2047]; //8K ROM

    initial begin
        $readmemh(FONT_MEM_FILE, rom);
    end

    always_ff @(posedge clk) begin
        data <= rom[addr];
    end
endmodule



module osd_font_color_pal (
    input  logic        clk,
    input  logic [3:0] addr,
	output logic [7:0] R,
	output logic [7:0] G,
	output logic [7:0] B
);

parameter  PAL_MEM_FILE = "";
    logic [23:0] PAL [0:15]; //48Bytes ROM 

    initial begin
        $readmemh(PAL_MEM_FILE, PAL);
    end

    always_ff @(posedge clk) begin
        R <= PAL[addr][23:16];
		G <= PAL[addr][15:8];
		B <= PAL[addr][7:0];
    end
endmodule


