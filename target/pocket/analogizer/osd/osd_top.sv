// Project: OSD Overlay
// File: osd_overlay.sv
// Description: Overlay module for displaying OSD (On-Screen Display) characters
//              on a VGA screen. It uses a character RAM and a font ROM to
//              generate the pixel data for the OSD characters.
// Author: @RndMnkIII
// Date: 2025-05-09
// License: MIT
//
`default_nettype none

module osd_top #(
    parameter int CLK_HZ = 32_000_000,
    parameter int DURATION_SEC = 4,
    parameter int COLS = 32,
    parameter int ROWS = 32,
    parameter int CHAR_RAM_SIZE = COLS * ROWS
)(
    input  logic        rot90,
    input  logic         clk,
    input  logic         reset,
    input  logic         pixel_ce,
    input  logic [7:0]   R_in,
    input  logic [7:0]   G_in,
    input  logic [7:0]   B_in,
    input  logic         hsync_in,
    input  logic         vsync_in,
    input  logic         hblank,
    input  logic         vblank,
    input  logic         key_left,
    input  logic         key_right,
    input  logic         key_up,
    input  logic         key_down,
    input  logic         key_A,
    output logic [7:0]   R_out,
    output logic [7:0]   G_out,
    output logic [7:0]   B_out,
    output logic         hsync_out,
    output logic         vsync_out,
    output logic [2:0]   hblank_out,
    output logic [2:0]   vblank_out,
    output logic signed [5:0] h_offset_out,
    output logic signed [4:0] v_offset_out,
    input logic        vid_mode_in,
    output logic osd_pause_out,
    //Analogizer settings
    input logic       analogizer_ready,
    input logic [3:0] analogizer_video_type,
    input logic [4:0] snac_game_cont_type,
    input logic [3:0] snac_cont_assignment
);

  // RAM de caracteres compartida
  logic [10:0] wr_addr, char_rd_addr;
  logic [7:0]  wr_data, char_code;
  logic        wr_en;
  logic       vid_mode;

    char_ram_dualport #(
        .ADDR_WIDTH(10), //1024 posiciones (32x32 caracteres)
        .DATA_WIDTH(8),
        .INIT_FILE("osd_analogizer_graffitti_32_32_RAM.mem")
    ) char_mem_inst (
        .clk(clk),
        .we_a(wr_en),
        .addr_a(wr_addr),
        .data_a(wr_data),
        .addr_b(char_rd_addr),
        .data_b(char_code)
    );

    logic [11:0] x_pix, y_pix;
    logic [11:0] width, height;
    logic        timing_ready;

    video_timing_tracker timing_inst (
        .clk(clk),
        .pixel_ce(pixel_ce),
        .hs(hsync_in),
        .vs(vsync_in),
        .hb(hblank),
        .vb(vblank),
        .x(x_pix),
        .y(y_pix),
        .width(width),
        .height(height),
        .ready(timing_ready)
    );

    logic signed [4:0] h_offset=$signed(5'sd0), v_offset=$signed(4'sd0);

    typedef enum logic [4:0] {
        INIT_IDLE, INIT_WAIT, INIT_NEXT, INIT_DONE,
        IDLE, COPY_OFFSET, UPDATE_H_0, UPDATE_H_1, UPDATE_H_2,
        UPDATE_V_0, UPDATE_V_1, UPDATE_V_2,
        WRITE_WIDTH, WAIT_WIDTH,
        WRITE_HEIGHT, WAIT_HEIGHT
    } state_t;

    state_t state;
    logic key_leftr, key_rightr, key_upr, key_downr, key_A_r;

    logic [7:0] ascii_sign, ascii_sign2, ascii_tens, ascii_units;
    logic [4:0] abs_val;
    logic [4:0] abs_val2;
    logic signed [4:0] val;

    localparam int H_POS = 16 * COLS + 17;
    localparam int V_POS = 17 * COLS + 17;
    localparam int WIDTH_POS = 18 * COLS + 13;
    localparam int HEIGHT_POS = 19 * COLS + 13;
    localparam int VIDEO_POS = 20 * COLS + 13;
    localparam int SNAC_DEV_POS = 21 * COLS + 13;
    localparam int SNAC_ASG_POS = 22 * COLS + 13;
    localparam int HZ_POS = 2 * COLS + 27;

    logic [10:0] wr_addr_manual;
    logic [7:0]  wr_data_manual;
    logic        wr_en_manual;
    logic wait_key;
    logic [2:0] data_info_idx;
    always_ff @(posedge clk) begin
        key_leftr <= key_left;
        key_rightr <= key_right;
        key_upr <= key_up;
        key_downr <= key_down;
        key_A_r <= key_A;
        
        if (reset) begin
            data_info_idx <= 0;
            h_offset <= $signed(5'sd0);
            v_offset <= $signed(5'sd0);
            state <= INIT_IDLE;
            init_done      <= 0;
            //str_index      <= 0;
            //str_base_addr  <= 0;
            //start_str      <= 0;
            //wr_en_manual   <= 0;
            wait_key       <= 0;
            //start_str      <= 0;
        end else begin
            wr_en_manual <= 0;
            vid_mode <= vid_mode_in;

        
            //State machine para escribir valores en la RAM ya convertidos a formato ASCII
            case (state)
                INIT_IDLE: begin
                    start_str <= 0;
                    // if(analogizer_ready) state <= INIT_WAIT;
                    // else state <= INIT_IDLE;
                    if (!wait_key && (key_leftr || key_rightr || key_downr || key_upr || key_A_r)) begin
                        if (key_leftr && (h_offset > -5'sd15)) h_offset <= h_offset + $signed(-5'sd1);
                        else if (key_rightr && (h_offset < 5'sd15)) h_offset <= h_offset + $signed(5'sd1);
                        if (key_upr && (v_offset > -5'sd15)) v_offset <= v_offset + $signed(-5'sd1);
                        else if (key_downr && (v_offset < 5'sd15)) v_offset <= v_offset + $signed(5'sd1);

                        //if(key_A_r) vid_mode <= ~vid_mode;
                        
                        state <= INIT_WAIT;
                        wait_key <= 1;
                    end
                end

                INIT_WAIT: begin
                    if (!busy_str) begin
                        if(start_str == 0) begin
                            case (data_info_idx)
                                3'd0: begin
                                    str_index     <= {2'b0,analogizer_video_type} + 6'd0; //see string_to_ram_writer
                                    str_base_addr <= VIDEO_POS;
                                    data_info_idx <= data_info_idx + 1;
                                    start_str     <= 1;
                                    state    <= INIT_NEXT;
                                end
                                3'd1: begin
                                    str_index     <= {1'b0,snac_game_cont_type} + 6'd16; //see string_to_ram_writer
                                    str_base_addr <= SNAC_DEV_POS;
                                    data_info_idx <= data_info_idx + 1;
                                    start_str     <= 1;
                                    state    <= INIT_NEXT;
                                end 
                                3'd2: begin
                                    str_index     <= {2'b0,snac_cont_assignment} + 6'd10; //see string_to_ram_writer
                                    str_base_addr <= SNAC_ASG_POS;
                                    data_info_idx <= data_info_idx + 1;
                                    start_str     <= 1;
                                    state    <= INIT_NEXT;
                                end 
                                3'd3: begin
                                    str_index     <= {5'b0,vid_mode} + 6'd36; //see string_to_ram_writer
                                    str_base_addr <= HZ_POS;
                                    data_info_idx <= data_info_idx + 1;
                                    start_str     <= 1;
                                    state    <= INIT_NEXT;
                                end 
                                default: begin
                                    data_info_idx <= 0; //importate: reiniciar data_info_idx o no se actualizara vid mode msg
                                    init_done <= 1;
                                    state <= INIT_DONE;
                                end
                            endcase
                        end
                    end
                    else  begin 
                        state <= INIT_WAIT;
                    end
                end
                

                INIT_NEXT: begin
                    start_str <= 0;
                    state <= INIT_WAIT;
                end

                INIT_DONE: begin
                    state <= IDLE;
                end
                IDLE: 
                    // if (!wait_key && (key_leftr || key_rightr || key_downr || key_upr || key_A_r)) begin
                    //     if (key_leftr && (h_offset > -5'sd15)) h_offset <= h_offset + $signed(-5'sd1);
                    //     else if (key_rightr && (h_offset < 5'sd15)) h_offset <= h_offset + $signed(5'sd1);
                    //     if (key_upr && (v_offset > -5'sd15)) v_offset <= v_offset + $signed(-5'sd1);
                    //     else if (key_downr && (v_offset < 5'sd15)) v_offset <= v_offset + $signed(5'sd1);
                    //     if(key_A_r) vid_mode <= vid_mode + 2'd1;
                    //     state <= COPY_OFFSET;
                    //     wait_key <= 1;
                    // end
                    state <= COPY_OFFSET;
                COPY_OFFSET:begin
                        ascii_sign  <= (h_offset < 0) ? 8'h2D : 8'h2B;
                        ascii_sign2 <= (v_offset < 0) ? 8'h2D : 8'h2B;
                        abs_val     <= (h_offset < 0) ? -h_offset : h_offset;
                        abs_val2    <= (v_offset < 0) ? -v_offset : v_offset;
                        state <= UPDATE_H_0;
                end

                UPDATE_H_0: begin
                    wr_addr_manual <= H_POS + 0; wr_data_manual <= ascii_sign; wr_en_manual <= 1;
                    ascii_tens  <= (abs_val >= 10) ? 8'h31 : 8'h20;
                    state <= UPDATE_H_1;
                end

                UPDATE_H_1: begin
                    wr_addr_manual <= H_POS + 1; wr_data_manual <= ascii_tens; wr_en_manual <= 1;
                    ascii_units <= 8'h30 + (abs_val % 10);
                    state <= UPDATE_H_2;
                end

                UPDATE_H_2: begin
                    wr_addr_manual <= H_POS + 2; wr_data_manual <= ascii_units; wr_en_manual <= 1;
                    state <= UPDATE_V_0;
                end

                UPDATE_V_0: begin
                    wr_addr_manual <= V_POS + 0; wr_data_manual <= ascii_sign2; wr_en_manual <= 1;
                    ascii_tens  <= (abs_val2 >= 10) ? 8'h31 : 8'h20;
                    state <= UPDATE_V_1;
                end

                UPDATE_V_1: begin
                    wr_addr_manual <= V_POS + 1; wr_data_manual <= ascii_tens; wr_en_manual <= 1;
                    ascii_units <= 8'h30 + (abs_val2 % 10);
                    state <= UPDATE_V_2;
                end
                UPDATE_V_2: begin
                    wr_addr_manual <= V_POS + 2; wr_data_manual <= ascii_units; wr_en_manual <= 1;

                    //Preparar escritura de width
                    writer_value <= width+1; //adjust for 0-based index
                    writer_base_addr <= WIDTH_POS;
                    start_writer <= 1;
                    state <= WRITE_WIDTH;
                    end

                WRITE_WIDTH: begin
                    start_writer <= 0;
                    state <= WAIT_WIDTH;
                end

                WAIT_WIDTH: begin
                    if (!busy_writer) begin
                        //Preparar escritura de height
                        writer_value     <= height+1; //adjust for 0-based index
                        writer_base_addr <= HEIGHT_POS;
                        start_writer     <= 1;
                        state            <= WRITE_HEIGHT;
                    end
                end

                WRITE_HEIGHT: begin
                    start_writer <= 0;
                    state <= WAIT_HEIGHT;
                end

                WAIT_HEIGHT: begin
                    if (!busy_writer)
                        state <= INIT_IDLE;
                        wait_key <= 0;
                end
            endcase 
        end        
    end

    // Señales para string_to_ram_writer
    logic start_str;
    logic busy_str;
    logic [5:0] str_index;
    logic [10:0] str_base_addr;
    logic wr_en_str;
    logic [10:0] wr_addr_str;
    logic [7:0] wr_data_str;
    logic init_done;

    // Instancia del módulo string_to_ram_writer
    string_to_ram_writer str_writer_inst (
        .clk(clk),
        .start(start_str),
        .string_index(str_index),
        .base_addr(str_base_addr),
        .wr_en(wr_en_str),
        .wr_addr(wr_addr_str),
        .wr_data(wr_data_str),
        .busy(busy_str)
    );

    logic start_writer, busy_writer;
    logic signed [13:0] writer_value;
    logic [10:0] writer_base_addr;
    logic wr_en_writer;
    logic [10:0] wr_addr_writer;
    logic [7:0] wr_data_writer;

    // Instancia única de bin_to_ascii_writer
    bin_to_ascii_writer #(.SHOW_SIGN(0)) writer_inst (
        .clk(clk),
        .start(start_writer),
        .value(writer_value),
        .base_addr(writer_base_addr),
        .wr_en(wr_en_writer),
        .wr_addr(wr_addr_writer),
        .wr_data(wr_data_writer),
        .busy(busy_writer)
    );

        // Multiplexor de acceso a la RAM de caracteres
    assign wr_en   = wr_en_str   | wr_en_writer   | wr_en_manual;
    assign wr_addr = wr_en_str   ? wr_addr_str    :
                 wr_en_writer ? wr_addr_writer : wr_addr_manual;
    assign wr_data = wr_en_str   ? wr_data_str    :
                 wr_en_writer ? wr_data_writer : wr_data_manual;    


    logic [24:0] video_osd; //transparent color+RGB
    logic [7:0] R_d1, R_d2, R_d3, G_d1, G_d2, G_d3,B_d1, B_d2, B_d3;
    logic hsync_d1, hsync_d2, hsync_d3, vsync_d1, vsync_d2, vsync_d3;
    logic hblank_d1, hblank_d2, hblank_d3, vblank_d1, vblank_d2, vblank_d3;
    logic [9:0] x_d1, x_d2, y_d1, y_d2;
    logic osd_d1, osd_d2;
    logic osd_active;
    logic disp_dbg;

    osd_timer #(.CLK_HZ(CLK_HZ), .DURATION_SEC(DURATION_SEC)) timer_inst (
        .clk(clk),
        .reset(reset),
        .enable(key_leftr || key_rightr || key_downr || key_upr || key_A_r),
        .active(osd_active)
    );

    assign osd_pause_out = osd_active;

    always_ff @(posedge clk) begin
         if (pixel_ce) begin
            R_d1 <= R_in; R_d2 <= R_d1; R_d3 <= R_d2;
            G_d1 <= G_in; G_d2 <= G_d1; G_d3 <= G_d2;
            B_d1 <= B_in; B_d2 <= B_d1; B_d3 <= B_d2;
            hsync_d1 <= hsync_in; hsync_d2 <= hsync_d1; // hsync_d3 <= hsync_d2;
            vsync_d1 <= vsync_in; vsync_d2 <= vsync_d1; // vsync_d3 <= vsync_d2;
            hblank_d1 <= hblank; hblank_d2 <= hblank_d1;// hblank_d3 <= hblank_d2;
            vblank_d1 <= vblank; vblank_d2 <= vblank_d1;// vblank_d3 <= vblank_d2;
            // x_d1 <= x_pix[9:0]; x_d2 <= x_d1;
            // y_d1 <= y_pix[9:0]; y_d2 <= y_d1;
            // osd_d1 <= osd_active; osd_d2 <= osd_d1;
         end
    end

    osd_overlay_4bpp #(
        .CHAR_WIDTH(8), .CHAR_HEIGHT(8),
        .SCREEN_COLS(COLS), .SCREEN_ROWS(ROWS)
    ) osd_inst (
        .rot90(rot90),
        .clk(clk),
        .reset(reset),
        .hblank(hblank),
        .vblank(vblank),
        .x(x_pix[9:0]),
        .y(y_pix[9:0]),
        .osd_active(osd_active),
        .video_out(video_osd),
        .addr_b(char_rd_addr),
        .char_code(char_code),
        .disp_dbg(disp_dbg)
    );

    // Color del OSD (gris), por ejemplo: 0xA0
    localparam [7:0] OSD_GRAY = 8'hA0;

    // Peso: 3/4 fondo + 1/4 OSD → (background >> 2) + (OSD >> 2)
    logic [7:0] Rgrayout, Ggrayout, Bgrayout;
    assign Rgrayout = (R_d2 >> 1) + (OSD_GRAY >> 2);
    assign Ggrayout = (G_d2 >> 1) + (OSD_GRAY >> 2);
    assign Bgrayout = (B_d2 >> 1) + (OSD_GRAY >> 2);

    //assign {R_out, G_out, B_out} = (y_pix[9:0] == 10'd0) ? 24'd0 : (video_osd[24] == 1'b0) ? video_osd[23:0] : (osd_active ? {Rgrayout,Ggrayout,Bgrayout} :{R_d2, G_d2, B_d2});
    assign {R_out, G_out, B_out} = (video_osd[24] == 1'b0) ? video_osd[23:0] : (osd_active ? {Rgrayout,Ggrayout,Bgrayout} :{R_d2, G_d2, B_d2});
    assign hsync_out = hsync_d2;
    assign vsync_out = vsync_d2;
    assign hblank_out = hblank_d2;
    assign vblank_out = vblank_d2;
    assign h_offset_out = h_offset;
    assign v_offset_out = v_offset;
    //assign vid_mode_out = vid_mode;
endmodule
