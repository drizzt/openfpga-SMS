//
// SMS core top-level for Analogue Pocket
//
// Wraps MiSTer SMS system.vhd (Master System / Game Gear / SG-1000) with the
// Pocket APF bridge, SDRAM ROM storage, raster video output, audio I2S and
// input mapping. Structure follows the openfpga-GBA port.
//
// Mode (sms/gg/sg1000) is written by the Chip32 loader from the cartridge
// file extension before the ROM is streamed in.
//

`default_nettype none

module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable,

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,

///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,

output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
//
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig

);

// not using the IR port, so turn off both the LED, and
// disable the receive circuit to save power
assign port_ir_tx = 0;
assign port_ir_rx_disable = 1;

// bridge endianness
assign bridge_endian_little = 0;

// cart is unused, so set all level translators accordingly
// directions are 0:IN, 1:OUT
assign cart_tran_bank3 = 8'hzz;
assign cart_tran_bank3_dir = 1'b0;
assign cart_tran_bank2 = 8'hzz;
assign cart_tran_bank2_dir = 1'b0;
assign cart_tran_bank1 = 8'hzz;
assign cart_tran_bank1_dir = 1'b0;
assign cart_tran_bank0 = 4'hf;
assign cart_tran_bank0_dir = 1'b1;
assign cart_tran_pin30 = 1'b0;
assign cart_tran_pin30_dir = 1'bz;
assign cart_pin30_pwroff_reset = 1'b0;
assign cart_tran_pin31 = 1'bz;
assign cart_tran_pin31_dir = 1'b0;

// Game Gear link (Gear-to-Gear) on the Pocket link port. Two-wire serial:
//   SO = TxD (Port C bit 4), SI = RxD (Port C bit 5).
// The GBA-style link cable crosses SO<->SI, which is exactly the real
// Gear-to-Gear TxD<->RxD crossover, so two Pockets link with a straight cable.
// SD/SCK stay idle (the standard cable carries no handshake line). The port is
// driven only in Game Gear mode with the link option on (link_active); otherwise
// it is tristated exactly as before. See link_active / si_sync / gg_link_out below.
assign port_tran_so      = link_active ? gg_link_out[4] : 1'bz; // TxD (PC4), push-pull
assign port_tran_so_dir  = link_active;                        // 1=OUT while linking
assign port_tran_si      = 1'bz;                               // RxD (PC5), always input
assign port_tran_si_dir  = 1'b0;
assign port_tran_sck     = 1'bz;
assign port_tran_sck_dir = 1'b0;
assign port_tran_sd      = 1'bz;
assign port_tran_sd_dir  = 1'b0;

// tie off PSRAM, unused (ROM lives in SDRAM, saves in BRAM)
assign cram0_a = 'h0;
assign cram0_dq = {16{1'bZ}};
assign cram0_clk = 0;
assign cram0_adv_n = 1;
assign cram0_cre = 0;
assign cram0_ce0_n = 1;
assign cram0_ce1_n = 1;
assign cram0_oe_n = 1;
assign cram0_we_n = 1;
assign cram0_ub_n = 1;
assign cram0_lb_n = 1;

assign cram1_a = 'h0;
assign cram1_dq = {16{1'bZ}};
assign cram1_clk = 0;
assign cram1_adv_n = 1;
assign cram1_cre = 0;
assign cram1_ce0_n = 1;
assign cram1_ce1_n = 1;
assign cram1_oe_n = 1;
assign cram1_we_n = 1;
assign cram1_ub_n = 1;
assign cram1_lb_n = 1;

// tie off SRAM, inactive
assign sram_a = 'h0;
assign sram_dq = {16{1'bZ}};
assign sram_oe_n  = 1;
assign sram_we_n  = 1;
assign sram_ub_n  = 1;
assign sram_lb_n  = 1;

assign dbg_tx = 1'bZ;
assign user1 = 1'bZ;
assign aux_scl = 1'bZ;
assign vpll_feed = 1'bZ;


// ============================================================
// Section 1: PLL & Clock Generation
// ============================================================

// Power-up NTSC clk_sys = 53.693175 MHz; runtime PLL reconfig switches the
// whole VCO to PAL (clk_sys = 53.203424 MHz), so all four outputs scale
// together and stay phase-related.
wire    clk_sys;            // 53.693175 MHz NTSC / 53.203424 MHz PAL, SMS core domain
wire    clk_sdram_ph;       // clk_sys, 180 deg: SDRAM clock (DDR-forwarded to pin)
wire    clk_vid;            // clk_sys/10, SMS dot clock
wire    clk_vid_90;         // clk_sys/10, 90 deg: video DDR
wire    pll_core_locked;
wire    pll_core_locked_s;
synch_3 s01(pll_core_locked, pll_core_locked_s, clk_74a);

// Power-on lock gate: the core is held in reset until the PLL first locks,
// but later lock dips must NOT reset it: the NTSC/PAL reconfig self-resets
// the PLL (pll_slf_rst) and briefly drops lock, and MiSTer keeps the core
// running through that (locked only re-inits the SDRAM controller there).
reg pll_ever_locked = 0;
always @(posedge clk_74a) if (pll_core_locked_s) pll_ever_locked <= 1;

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;

mf_pllbase mp1 (
    .refclk     ( clk_74a ),
    .rst        ( 0 ),
    .outclk_0   ( clk_sys ),
    .outclk_1   ( clk_sdram_ph ),
    .outclk_2   ( clk_vid ),
    .outclk_3   ( clk_vid_90 ),
    .locked     ( pll_core_locked ),
    .reconfig_to_pll   ( reconfig_to_pll ),
    .reconfig_from_pll ( reconfig_from_pll )
);

// NTSC/PAL runtime PLL reconfiguration (MiSTer SMS.sv pattern).
// Both clk_sys values share M_int=8 and every C divider, so switching
// rewrites only the DSM fractional-K word: register 7 of the reconfig IP
// (0 = mode register, written 0 = waitrequest mode; 2 = start).
// WAIT_FOR_LOCK=1 holds cfg_waitrequest until the PLL relocks; the core
// keeps running through the brief lock drop (pll_ever_locked above), with
// only the SDRAM controller re-initializing, MiSTer parity.
//
// The NTSC K word must match pll_fractional_division in mf_pllbase_0002.v
// (the PLL's power-up state): retune both together.
localparam [31:0] NTSC_FRAC_K = 32'd2910634261;  // 53.693175 MHz
localparam [31:0] PAL_FRAC_K  = 32'd2570680398;  // 53.203424 MHz

wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg  [31:0] cfg_data;

pll_reconfig pll_reconfig_inst (
    .mgmt_clk         ( clk_74a ),
    .mgmt_reset       ( 1'b0 ),
    .mgmt_waitrequest ( cfg_waitrequest ),
    .mgmt_read        ( 1'b0 ),
    .mgmt_readdata    ( ),
    .mgmt_write       ( cfg_write ),
    .mgmt_address     ( cfg_address ),
    .mgmt_writedata   ( cfg_data ),
    .reconfig_to_pll  ( reconfig_to_pll ),
    .reconfig_from_pll( reconfig_from_pll )
);

// Reconfig FSM state at module scope so the deterministic-reboot reset block
// below can synchronize it to clk_sys directly: pal_r = the tv system the PLL
// is being driven to; (state != 0) | cfg_waitrequest = a reconfig is in flight.
// No intermediate clk_74a registers: synch_3 already registers its input, and
// keeping these off the marginal pll_reconfig domain avoids the STA hit the
// earlier pal_cfg/pal_busy pre-registers caused (which had forced a SEED reroll).
reg [2:0] state = 0;
reg       pal_r = 0;

always @(posedge clk_74a) begin
    cfg_write <= 0;

    if (!cfg_waitrequest) begin
        if (state) state <= state + 1'd1;
        case (state)
            1: begin
                cfg_address <= 0;        // mode register: 0 = waitrequest mode
                cfg_data    <= 0;
                cfg_write   <= 1;
            end
            5: begin
                cfg_address <= 7;        // DSM fractional K
                cfg_data    <= pal_r ? PAL_FRAC_K : NTSC_FRAC_K;
                cfg_write   <= 1;
            end
            7: begin
                cfg_address <= 2;        // start reconfiguration
                cfg_data    <= 0;
                cfg_write   <= 1;
            end
        endcase
    end

    // pal is bridge-written on this same clk_74a domain (no CDC needed).
    // Trigger checked LAST so a toggle landing mid-sequence restarts it
    // (the restart's state <= 1 overrides the increment above) and the
    // start write never commits a stale K. Held off until the download
    // path is quiescent: the reconfig glitches clk_sys/the SDRAM clock and
    // the controller drops in-flight ROM writes while re-initializing:
    // the persisted PAL setting is replayed by the OS at launch and can
    // otherwise overlap the ROM stream. (The opposite order, reconfig
    // triggered just before a download, is safe by construction: relock
    // completes in well under a millisecond, while the Chip32 still has
    // ms-scale file-open work before the first cart byte arrives.)
    if (pal != pal_r && dl_quiet == 0) begin
        state <= 1;
        pal_r <= pal;
    end
end

// The Chip32 downloading=0 write can land before the data_loader FIFO tail
// drains to SDRAM (documented invariant, see Section 5), so the flag alone
// is not quiescence: hold the reconfig off for ~1.8 ms past the falling
// edge, far beyond any FIFO tail at clkref pacing.
reg [16:0] dl_quiet = 0;
always @(posedge clk_74a) begin
    if (downloading)         dl_quiet <= 17'h1FFFF;
    else if (dl_quiet != 0)  dl_quiet <= dl_quiet - 1'd1;
end

// SDRAM clock pin: forward the 180-degree PLL output through a DDR output
// cell (equivalent to MiSTer's inverted-clock altddio_out)
pin_ddio_clk dramclk_ddr (
    .datain_h ( 1'b1 ),
    .datain_l ( 1'b0 ),
    .outclock ( clk_sdram_ph ),
    .dataout  ( dram_clk )
);

// Clock enables, replicated verbatim from MiSTer SMS.sv.
// clkd counts 0..29 on negedge clk_sys:
//   ce_vdp ÷5, ce_pix ÷10, ce_cpu ÷15 (phase at 9/24 for VDPTEST), ce_sp ÷2
reg ce_cpu;
reg ce_vdp;
reg ce_pix;
reg ce_sp;
always @(negedge clk_sys) begin
    reg [4:0] clkd;

    ce_sp <= clkd[0];
    ce_vdp <= 0;//div5
    ce_pix <= 0;//div10
    ce_cpu <= 0;//div15
    clkd <= clkd + 1'd1;
    if (clkd==29) begin
        clkd <= 0;
        ce_vdp <= 1;
        ce_pix <= 1;
    end else if (clkd==24) begin
        ce_cpu <= 1;  //-- changed cpu phase to please VDPTEST HCounter test;
        ce_vdp <= 1;
    end else if (clkd==19) begin
        ce_vdp <= 1;
        ce_pix <= 1;
    end else if (clkd==14) begin
        ce_vdp <= 1;
    end else if (clkd==9) begin
        ce_cpu <= 1;
        ce_vdp <= 1;
        ce_pix <= 1;
    end else if (clkd==4) begin
        ce_vdp <= 1;
    end
end


// ============================================================
// Section 2: Bridge Command Handler
// ============================================================

wire            reset_n;
wire    [31:0]  cmd_bridge_rd_data;

wire            status_boot_done  = pll_core_locked_s;
wire            status_setup_done = pll_core_locked_s;
wire            status_running    = reset_n;

wire            dataslot_requestread;
wire    [15:0]  dataslot_requestread_id;
wire            dataslot_requestread_ack = 1;
wire            dataslot_requestread_ok = 1;

wire            dataslot_requestwrite;
wire    [15:0]  dataslot_requestwrite_id;
wire    [31:0]  dataslot_requestwrite_size;
wire            dataslot_requestwrite_ack = 1;
wire            dataslot_requestwrite_ok = 1;

wire            dataslot_update;
wire    [15:0]  dataslot_update_id;
wire    [31:0]  dataslot_update_size;

wire            dataslot_allcomplete;

wire    [31:0]  rtc_epoch_seconds;
wire    [31:0]  rtc_date_bcd;
wire    [31:0]  rtc_time_bcd;
wire            rtc_valid;

// Savestates (used by the OS for sleep/wake): one 64 KB slot served
// over the bridge at 0x4xxxxxxx by savestate_controller.
wire            savestate_supported = 1;
wire    [31:0]  savestate_addr = 32'h40000000;
wire    [31:0]  savestate_size = 32'h00010000;
wire    [31:0]  savestate_maxloadsize = 32'h00010000;

wire            savestate_start;
wire            savestate_start_ack;
wire            savestate_start_busy;
wire            savestate_start_ok;
wire            savestate_start_err;

wire            savestate_load;
wire            savestate_load_ack;
wire            savestate_load_busy;
wire            savestate_load_ok;
wire            savestate_load_err;

wire            osnotify_inmenu;

// target dataslot commands unused (saves go through data_loader/unloader)
wire            target_dataslot_read = 0;
wire            target_dataslot_write = 0;
wire            target_dataslot_getfile = 0;
wire            target_dataslot_openfile = 0;

wire            target_dataslot_ack;
wire            target_dataslot_done;
wire    [2:0]   target_dataslot_err;

wire    [15:0]  target_dataslot_id = 0;
wire    [31:0]  target_dataslot_slotoffset = 0;
wire    [31:0]  target_dataslot_bridgeaddr = 0;
wire    [31:0]  target_dataslot_length = 0;

wire    [31:0]  target_buffer_param_struct = 0;
wire    [31:0]  target_buffer_resp_struct = 0;

// ---- Datatable write: communicate save size to Pocket OS ----
// Continuously write the NVRAM size to datatable[3] (save slot at
// data_slots index 1: 1*2+1 = 3). The Pocket OS reads this value on core
// exit to determine save writeback size. Continuous (not one-shot) because
// the OS may overwrite the entry during its own bookkeeping.
wire    [9:0]   datatable_addr = 10'd3;
wire            datatable_wren = pll_core_locked_s;
wire    [31:0]  datatable_data = 32'd32768;
wire    [31:0]  datatable_q;

core_bridge_cmd icb (

    .clk                    ( clk_74a ),
    .reset_n                ( reset_n ),

    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_rd              ( bridge_rd ),
    .bridge_rd_data         ( cmd_bridge_rd_data ),
    .bridge_wr              ( bridge_wr ),
    .bridge_wr_data         ( bridge_wr_data ),

    .status_boot_done       ( status_boot_done ),
    .status_setup_done      ( status_setup_done ),
    .status_running         ( status_running ),

    .dataslot_requestread       ( dataslot_requestread ),
    .dataslot_requestread_id    ( dataslot_requestread_id ),
    .dataslot_requestread_ack   ( dataslot_requestread_ack ),
    .dataslot_requestread_ok    ( dataslot_requestread_ok ),

    .dataslot_requestwrite      ( dataslot_requestwrite ),
    .dataslot_requestwrite_id   ( dataslot_requestwrite_id ),
    .dataslot_requestwrite_size ( dataslot_requestwrite_size ),
    .dataslot_requestwrite_ack  ( dataslot_requestwrite_ack ),
    .dataslot_requestwrite_ok   ( dataslot_requestwrite_ok ),

    .dataslot_update            ( dataslot_update ),
    .dataslot_update_id         ( dataslot_update_id ),
    .dataslot_update_size       ( dataslot_update_size ),

    .dataslot_allcomplete   ( dataslot_allcomplete ),

    .rtc_epoch_seconds      ( rtc_epoch_seconds ),
    .rtc_date_bcd           ( rtc_date_bcd ),
    .rtc_time_bcd           ( rtc_time_bcd ),
    .rtc_valid              ( rtc_valid ),

    .savestate_supported    ( savestate_supported ),
    .savestate_addr         ( savestate_addr ),
    .savestate_size         ( savestate_size ),
    .savestate_maxloadsize  ( savestate_maxloadsize ),

    .savestate_start        ( savestate_start ),
    .savestate_start_ack    ( savestate_start_ack ),
    .savestate_start_busy   ( savestate_start_busy ),
    .savestate_start_ok     ( savestate_start_ok ),
    .savestate_start_err    ( savestate_start_err ),

    .savestate_load         ( savestate_load ),
    .savestate_load_ack     ( savestate_load_ack ),
    .savestate_load_busy    ( savestate_load_busy ),
    .savestate_load_ok      ( savestate_load_ok ),
    .savestate_load_err     ( savestate_load_err ),

    .osnotify_inmenu        ( osnotify_inmenu ),

    .target_dataslot_read       ( target_dataslot_read ),
    .target_dataslot_write      ( target_dataslot_write ),
    .target_dataslot_getfile    ( target_dataslot_getfile ),
    .target_dataslot_openfile   ( target_dataslot_openfile ),

    .target_dataslot_ack        ( target_dataslot_ack ),
    .target_dataslot_done       ( target_dataslot_done ),
    .target_dataslot_err        ( target_dataslot_err ),

    .target_dataslot_id         ( target_dataslot_id ),
    .target_dataslot_slotoffset ( target_dataslot_slotoffset ),
    .target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
    .target_dataslot_length     ( target_dataslot_length ),

    .target_buffer_param_struct ( target_buffer_param_struct ),
    .target_buffer_resp_struct  ( target_buffer_resp_struct ),

    .datatable_addr         ( datatable_addr ),
    .datatable_wren         ( datatable_wren ),
    .datatable_data         ( datatable_data ),
    .datatable_q            ( datatable_q )

);


// ============================================================
// Section 3: Bridge Read Mux + Control Registers
// ============================================================

wire [31:0] save_read_bridge_data;
wire [31:0] ss_bridge_rd_data;

always @(*) begin
    casex (bridge_addr)
    32'h2xxxxxxx: begin
        bridge_rd_data <= save_read_bridge_data;
    end
    32'h4xxxxxxx: begin
        bridge_rd_data <= ss_bridge_rd_data;
    end
    32'hF8xxxxxx: begin
        bridge_rd_data <= cmd_bridge_rd_data;
    end
    default: begin
        bridge_rd_data <= 0;
    end
    endcase
end

// ---- Control registers (clk_74a domain) ----
// 0x00000000  downloading flag, written 1/0 by Chip32 around the cart loadf
// 0x00000004  mode: 0=sms, 1=gg, 2=sg1000, written by Chip32 before loading
// 0x00000080  region: 0=US/EU (Export), 1=Japan          [interact.json]
// 0x00000084  FM sound: 0=enabled, 1=disabled            [interact.json]
// 0x00000088  sprites per line: 0=standard, 1=all        [interact.json]
// 0x0000008C  GG resolution: 0=standard 160x144, 1=ext.  [interact.json]
// 0x00000090  TV system: 0=NTSC, 1=PAL (SMS/SG-1000)     [interact.json]
// 0x00000094  blank border: 0=BG color, 1=black masked left column [interact.json]
// 0x00000098  BIOS disable: 0=internal boot ROM on, 1=off (SMS only); auto-resets [interact.json]
// 0x0000009C  link enable: 0=off, 1=on (Game Gear link, GG only)  [interact.json]
// 0x000000A0  mapper select: 0=auto,1=Sega,2=Codemasters,3=Korean,4=linear,5=Dahjee; auto-resets [interact.json]
// 0x000000A4  legacy palette: 0=SMS VDP colors, 1=TMS9918 colors (SMS only) [interact.json]
// 0xF0000000  reset core action                          [interact.json]

reg        downloading = 0;
reg  [1:0] mode = 0;
reg        region = 0;
reg        fm_disable = 0;
reg        sprites_all = 0;
reg        gg_ext_res = 0;
reg        pal = 0;
reg        blank_border = 0;
reg        bios_disable = 0;
reg        link_enable = 0;
reg  [2:0] mapper_sel = 0;
reg        tms_palette = 0;

localparam [13:0] RESET_PULSE = 14'd8000;  // ~108 us at 74.25 MHz
reg [13:0] reset_counter = 0;
wire       core_reset = (reset_counter != 0);

always @(posedge clk_74a) begin
    if (reset_counter != 0)
        reset_counter <= reset_counter - 1;

    if (bridge_wr) begin
        casex (bridge_addr)
        32'h00000000: downloading <= bridge_wr_data[0];
        32'h00000004: mode        <= bridge_wr_data[1:0];
        32'h00000080: region      <= bridge_wr_data[0];
        32'h00000084: fm_disable  <= bridge_wr_data[0];
        32'h00000088: sprites_all <= bridge_wr_data[0];
        32'h0000008C: gg_ext_res  <= bridge_wr_data[0];
        32'h00000090: pal         <= bridge_wr_data[0];
        32'h00000094: blank_border <= bridge_wr_data[0];
        // BIOS and Mapper only take effect at machine start (boot ROM gate /
        // cartridge bank init), so a mid-game change is silent until reset.
        // Pulse the reset counter on write to auto-reboot under the new setting.
        32'h00000098: begin bios_disable <= bridge_wr_data[0]; reset_counter <= RESET_PULSE; end
        32'h0000009C: link_enable  <= bridge_wr_data[0];
        32'h000000A0: begin mapper_sel <= bridge_wr_data[2:0]; reset_counter <= RESET_PULSE; end
        32'h000000A4: tms_palette  <= bridge_wr_data[0];
        32'hF0000000: reset_counter <= RESET_PULSE;
        endcase
    end
end

// ---- CDC to clk_sys ----
wire       downloading_s;
wire [1:0] mode_s;
wire       region_s;
wire       fm_disable_s;
wire       sprites_all_s;
wire       gg_ext_res_s;
wire       pal_s;
wire       blank_border_s;
wire       bios_disable_s;
wire       link_enable_s;
wire [2:0] mapper_sel_s;
wire       tms_palette_s;
wire       reset_n_s;
wire       core_reset_s;
wire       dataslot_allcomplete_s;

synch_3 #(.WIDTH(18)) settings_sync (
    {downloading,   mode,   region,   fm_disable,   sprites_all,   gg_ext_res,   pal,   blank_border,   bios_disable,   link_enable,   mapper_sel,   tms_palette,   reset_n,   core_reset,   dataslot_allcomplete},
    {downloading_s, mode_s, region_s, fm_disable_s, sprites_all_s, gg_ext_res_s, pal_s, blank_border_s, bios_disable_s, link_enable_s, mapper_sel_s, tms_palette_s, reset_n_s, core_reset_s, dataslot_allcomplete_s},
    clk_sys
);

// Configured-pal status (clk_74a -> clk_sys) for the deterministic-reboot reset.
// pal_r and the in-flight term are fed straight into synch_3 (which registers
// its input internally), so no clk_74a pre-register FFs sit on the marginal
// pll_reconfig domain.
wire pal_cfg_s, pal_busy_s;
synch_3 #(.WIDTH(2)) pal_cfg_sync (
    {pal_r,     (state != 0) | cfg_waitrequest},
    {pal_cfg_s, pal_busy_s},
    clk_sys
);

// Mode-derived signals (mirror MiSTer SMS.sv extension handling)
wire gg          = (mode_s == 2'd1);
wire palettemode = (mode_s == 2'd2);   // SG-1000: TMS9918 fixed palette
wire ggres       = ~gg_ext_res_s & gg; // MiSTer: ggres = ~status[39] & gg
// Internal boot ROM (mboot.mif = Bock's SMS Boot Loader, free homebrew) runs
// only in SMS mode: BIOS-dependent carts (e.g. Shadow Dancer) need it to init
// the machine and hand off to the cartridge via port $3E. mboot is an SMS
// program, so it is forced OFF for GG (mode 1) and SG-1000 (mode 2). The
// per-core BIOS toggle (interact id 45, default Internal) lets the user disable
// the ~1 s SEGA splash; per-game override is possible via /Presets/.
wire bios_en     = (mode_s == 2'd0) & ~bios_disable_s;

// ---- Game Gear link (drives the port_tran_* assigns in Section 2) ----
// Active only in Game Gear mode with the link option enabled. gg_link_out is the
// SMS core's open-drain Port C drive; we expose bit 4 (TxD) on SO. The incoming
// RxD line (the other Pocket's TxD on SI) is async to clk_sys, so it is passed
// through the project's standard CDC primitive before reaching Port C bit 5 (the
// UART RX sampler in io.vhd adds further ce_cpu-rate filtering on top).
wire [6:0] gg_link_out;
wire       link_active = link_enable_s & gg;
wire       si_sync;
synch_2 si_link_sync (.i(port_tran_si), .o(si_sync), .clk(clk_sys), .rise(), .fall());


// ============================================================
// Section 4: Reset
// ============================================================

// Deterministic boot/reboot: the fix for the intermittent PAL BIOS-boot sprite
// corruption (Shadow Dancer). Two cooperating ideas, replacing earlier timer
// guesses that only shifted the probability:
//
//  * pal_not_ready holds the core in reset until the PLL is actually running at
//    the REQUESTED tv system (pal_cfg_s == pal_s) with no reconfig in flight
//    (pal_busy_s). One term covers the whole pal path: the ~1.8 ms dl_quiet
//    deferral, the reconfig + relock, and an unbounded-late OS replay of the
//    persisted setting: each just becomes one clean, held reboot. A live
//    NTSC<->PAL toggle is thus a clean atomic reboot, never a mid-frame flip.
//
//  * phase_hold delays the FINAL release until video.vhd is at frame top
//    (vx==vy==0). video.vhd has no reset and free-runs, so otherwise the CPU
//    leaves reset at a RANDOM scanline and the BIOS->cart handoff lands at a
//    random phase: the root cause (Reset Core reproduces it identically, with
//    no reconfig at all). Pinning the release phase makes every cold boot AND
//    every Reset Core start mboot at the same scan position, so a BIOS-dependent
//    cart's one-time sprite-VRAM setup lands in the same safe part of the frame.
//
// ~pll_ever_locked (monotonic, single-bit) covers power-up before first lock.
wire pal_not_ready = (pal_s != pal_cfg_s) | pal_busy_s;

wire core_hold = ~reset_n_s | core_reset_s | ~pll_ever_locked | downloading_s
               | ~dataslot_allcomplete_s | pal_not_ready;

// WRAM clear on reset (MiSTer SMS.sv pattern; 8 KB: systeme/sc3000 are
// hardwired off, so system.vhd never drives ram_a[13])
reg [12:0] ram_clr_addr;
reg        ram_clr_run = 0;

always @(posedge clk_sys) begin
    if (core_hold) begin
        ram_clr_addr <= 0;
        ram_clr_run  <= 1'b1;
    end else if (ram_clr_run) begin
        ram_clr_addr <= ram_clr_addr + 1'd1;
        if (ram_clr_addr == 13'h1FFF) begin
            ram_clr_run <= 1'b0;
        end
    end
end

// Phase-aligned release: re-arm whenever the core is not otherwise ready, then
// drop only at frame top. Bounded by one frame (~16-20 ms).
reg phase_hold = 1'b1;
always @(posedge clk_sys) begin
    if (core_hold | ram_clr_run)       phase_hold <= 1'b1;
    else if (vx == 9'd0 && vy == 9'd0) phase_hold <= 1'b0;
end

wire reset_active = core_hold | ram_clr_run | phase_hold;

// Video-timing pal latched only while held: video.vhd then sees a STABLE pal for
// the machine's whole life (MiSTer parity), so a live pal_s change can never
// switch its 262<->313 line wrap mid-frame.
reg pal_machine = 1'b0;
always @(posedge clk_sys) if (reset_active) pal_machine <= pal_s;

// dbr: high once a cartridge has been loaded (no eject on Pocket)
reg dbr = 0;
always @(posedge clk_sys) begin
    if (downloading_s) begin
        dbr <= 1;
    end
end


// ============================================================
// Section 5: ROM Download Path
//   bridge 0x1xxxxxxx → data_loader (16-bit) → FIFO → byte FSM →
//     • SDRAM write (rom_wr toggle handshake)
//     • system ROMCL/ROMAD/ROMDT/ROMEN byte stream (mapper auto-detect)
//     • cart_mask / cart_mask512 / cart_sz512 / ysj_quirk tracking
// ============================================================

wire        rom_loader_wr;
wire [27:0] rom_loader_addr;
wire [15:0] rom_loader_data;

// 16-bit words every >=24 clk_sys cycles: two words per 32-bit APF write
// (≈48 cycles/word vs ≈54-cycle APF inflow), and the byte FSM drains one
// 16-bit word in two ce_pix-paced SDRAM windows (≈20 cycles): both fit.
data_loader #(
    .ADDRESS_MASK_UPPER_4   ( 4'h1 ),
    .ADDRESS_SIZE           ( 28 ),
    .OUTPUT_WORD_SIZE       ( 2 ),
    .WRITE_MEM_CLOCK_DELAY  ( 24 )
) rom_data_loader (
    .clk_74a            ( clk_74a ),
    .clk_memory         ( clk_sys ),

    .bridge_wr          ( bridge_wr ),
    .bridge_endian_little ( bridge_endian_little ),
    .bridge_addr        ( bridge_addr ),
    .bridge_wr_data     ( bridge_wr_data ),

    .write_en           ( rom_loader_wr ),
    .write_addr         ( rom_loader_addr ),
    .write_data         ( rom_loader_data )
);

// The Chip32 clears the downloading flag in a bridge write that can land
// while the last words are still draining through the data_loader FIFO, so
// the load path is only cleared at the START of a download and keeps
// draining after the flag falls.
reg  prev_downloading = 0;
always @(posedge clk_sys) prev_downloading <= downloading_s;
wire rom_dl_start = downloading_s & ~prev_downloading;

// Small skid FIFO (4 deep) between the paced loader and the byte FSM
reg [40:0] rom_fifo [3:0];          // {addr[24:0], data[15:0]}
reg  [2:0] rom_fifo_wptr = 0;
reg  [2:0] rom_fifo_rptr = 0;
wire       rom_fifo_empty = (rom_fifo_wptr == rom_fifo_rptr);

always @(posedge clk_sys) begin
    if (rom_loader_wr) begin
        rom_fifo[rom_fifo_wptr[1:0]] <= {rom_loader_addr[24:0], rom_loader_data};
        rom_fifo_wptr <= rom_fifo_wptr + 1'd1;
    end
    if (rom_dl_start) begin
        rom_fifo_wptr <= 0;
    end
end

// Byte FSM: two SDRAM byte writes per 16-bit word, MiSTer rom_wr toggle
// protocol. romwr_a/romwr_d feed both the SDRAM controller and (with the
// rom_byte_wr pulse) the system ROMEN port and download tracking below.
reg         rom_wr = 0;
wire        sd_wrack;
reg  [24:0] romwr_a = 0;
reg   [7:0] romwr_d = 0;

reg         rom_byte_wr = 0;        // 1-cycle pulse → system ROMEN

reg  [15:0] cur_word;
reg  [24:0] cur_addr;
reg  [1:0]  rom_ld_state = 0;       // 0=idle, 1=wait ack byte0, 2=wait ack byte1

wire [40:0] rom_fifo_head = rom_fifo[rom_fifo_rptr[1:0]];

always @(posedge clk_sys) begin
    rom_byte_wr <= 0;

    if (rom_dl_start) begin
        rom_ld_state <= 0;
        rom_fifo_rptr <= 0;
    end else begin
        case (rom_ld_state)
        2'd0: begin
            if (~rom_fifo_empty) begin
                {cur_addr, cur_word} <= rom_fifo_head;
                rom_fifo_rptr <= rom_fifo_rptr + 1'd1;

                romwr_a <= rom_fifo_head[40:16];
                romwr_d <= rom_fifo_head[7:0];
                rom_wr  <= ~rom_wr;
                rom_byte_wr <= 1;

                rom_ld_state <= 2'd1;
            end
        end
        2'd1: begin
            if (rom_wr == sd_wrack) begin
                romwr_a <= cur_addr + 1'd1;
                romwr_d <= cur_word[15:8];
                rom_wr  <= ~rom_wr;
                rom_byte_wr <= 1;

                rom_ld_state <= 2'd2;
            end
        end
        2'd2: begin
            if (rom_wr == sd_wrack) begin
                rom_ld_state <= 2'd0;
            end
        end
        default: rom_ld_state <= 0;
        endcase
    end
end

// Cartridge size masks, 512-byte header detection and Ys (Japan) quirk
// (replicates MiSTer SMS.sv download tracking)
reg [21:0] cart_mask = 0, cart_mask512 = 0;
reg        cart_sz512 = 0;
reg        ysj_quirk = 0;
reg [31:0] cart_id;

// Per-ROM signature fed to savestates.ss_game_id so the engine can reject a
// state saved under a different cartridge. Rolling hash over the cart download
// stream, identical to MiSTer SMS.sv (seed = FNV-1a offset basis, then per
// byte: rotate left 1, XOR the byte, XOR three address bits). The Pocket BIOS
// is the internal mboot.mif (BIOSWEN/ext_bios_loaded tied off), so it never
// reaches this stream and rom_byte_wr covers cartridge bytes only.
reg [31:0] ss_game_id = 32'h00000000;

always @(posedge clk_sys) begin
    if (rom_dl_start) begin
        ysj_quirk  <= 0;
        ss_game_id <= 32'h811C9DC5;
    end

    if (rom_byte_wr) begin
        ss_game_id <= {ss_game_id[30:0], ss_game_id[31]}
                    ^ {24'd0, romwr_d}
                    ^ {7'd0, romwr_a[0], romwr_a[8], romwr_a[16]};

        cart_mask    <= (romwr_a == 0)   ? 22'd0 : (cart_mask    | romwr_a[21:0]);
        cart_mask512 <= (romwr_a == 512) ? 22'd0 : (cart_mask512 | (romwr_a[21:0] - 10'd512));
        // Headered dumps end at size = N*1024 + 512, so the final byte
        // address has low 10 bits of 10'h1FF. Latched per byte (the last
        // one wins) rather than on the download-end edge, which can fire
        // before the FIFO tail has drained.
        cart_sz512   <= (romwr_a[9:0] == 10'h1FF);

        if (romwr_a == 'h7ffc) cart_id[31:24] <= romwr_d;
        if (romwr_a == 'h7ffd) cart_id[23:16] <= romwr_d;
        if (romwr_a == 'h7ffe) cart_id[15:08] <= romwr_d;
        if (romwr_a == 'h7fff) cart_id[07:00] <= romwr_d;
        if (romwr_a == 'h8000) begin
            if (cart_id == 32'h13_70_01_4F) ysj_quirk <= 1; // Ys (Japan) forces VDP version 1
        end
    end
end


// ============================================================
// Section 6: SDRAM (MiSTer rtl/sdram.sv at clk_sys, clkref-paced)
// ============================================================

wire [21:0] ram_addr;       // ROM address from system
wire  [7:0] ram_dout;       // ROM data to system
wire        ram_rd;         // ROM read request from system

sdram ram (
    .SDRAM_DQ   ( dram_dq ),
    .SDRAM_A    ( dram_a ),
    .SDRAM_DQML ( dram_dqm[0] ),
    .SDRAM_DQMH ( dram_dqm[1] ),
    .SDRAM_BA   ( dram_ba ),
    .SDRAM_nCS  ( ),                // Pocket SDRAM has no CS pin (always selected)
    .SDRAM_nWE  ( dram_we_n ),
    .SDRAM_nRAS ( dram_ras_n ),
    .SDRAM_nCAS ( dram_cas_n ),
    .SDRAM_CKE  ( dram_cke ),

    .init       ( ~pll_core_locked ),
    .clk        ( clk_sys ),
    .clkref     ( downloading_s ? ce_pix : ce_cpu ),

    .waddr      ( romwr_a ),
    .din        ( romwr_d ),
    .we         ( rom_wr ),
    .we_ack     ( sd_wrack ),

    .raddr      ( cart_sz512 ? (ram_addr + 10'd512) & cart_mask512 : ram_addr & cart_mask ),
    .dout       ( ram_dout ),
    .rd         ( ram_rd ),
    .rd_rdy     ( )
);


// ============================================================
// Section 6b: Savestate Wires (engine lives in Section 10b; the
// WRAM/NVRAM port muxes are in Sections 7 and 8)
// ============================================================

// State capture/restore only makes sense with a cart loaded and the core
// running (Pocket analogue of MiSTer's ss_state_allowed = dbr | ss_bios_mode).
// dbr goes high at download start and never clears here, so the cart case
// covers runtime; the extra guards also forbid SS while the boot ROM scans
// slots. savestates.sv hangs waiting for a Z80 instruction boundary otherwise:
// the controller errors out instead.
wire        allow_ss = dbr & ~reset_active & ~downloading_s & dataslot_allcomplete_s;

wire        ss_save, ss_load;
wire        ss_freeze;

wire [211:0] ss_z80_reg, ss_z80_dir;
wire         ss_z80_set;
wire         ss_z80_m1_n, ss_z80_mreq_n;
wire   [1:0] ss_z80_iset;
wire [127:0] ss_vdp_regs, ss_vdp_regs_in;
wire         ss_vdp_regs_set;
wire [383:0] ss_vdp_cram;
wire   [4:0] ss_cram_A;
wire  [11:0] ss_cram_D;
wire         ss_cram_wr;
wire         ss_vram_en;
wire  [14:0] ss_vram_A, ss_vram_WA;
wire   [7:0] ss_vram_D, ss_vram_WD;
wire         ss_vram_WE;
wire  [55:0] ss_psg_out, ss_psg_in;
wire         ss_psg_set;
wire  [63:0] ss_mapper_out, ss_mapper_in;
wire         ss_mapper_set;
wire  [31:0] ss_io_out, ss_io_in;
wire         ss_io_set;
wire  [21:0] ss_video_state_out, ss_video_state_in;
wire         ss_video_state_set;
wire  [13:0] ss_wram_A, ss_wram_WA;
wire   [7:0] ss_wram_WD;
wire         ss_wram_WE;
wire  [12:0] ss_nvram_A, ss_nvram_WA;
wire   [7:0] ss_nvram_WD;
wire         ss_nvram_WE;

wire  [28:0] ss_ddram_addr;
wire  [63:0] ss_ddram_din, ss_ddram_dout;
wire   [7:0] ss_ddram_be, ss_ddram_burstcnt;
wire         ss_ddram_we, ss_ddram_rd;
wire         ss_ddram_dout_ready, ss_ddram_busy;


// ============================================================
// Section 7: Cart Save (NVRAM 32 KB BRAM, bridge 0x2xxxxxxx)
// ============================================================

wire [14:0] nvram_a;
wire        nvram_we;
wire  [7:0] nvram_d;
wire  [7:0] nvram_q;

wire        save_loader_wr;
wire [27:0] save_loader_addr;
wire  [7:0] save_loader_data;

data_loader #(
    .ADDRESS_MASK_UPPER_4   ( 4'h2 ),
    .ADDRESS_SIZE           ( 28 ),
    .OUTPUT_WORD_SIZE       ( 1 ),
    .WRITE_MEM_CLOCK_DELAY  ( 4 )       // BRAM write, minimal delay
) save_data_loader (
    .clk_74a            ( clk_74a ),
    .clk_memory         ( clk_sys ),

    .bridge_wr          ( bridge_wr ),
    .bridge_endian_little ( bridge_endian_little ),
    .bridge_addr        ( bridge_addr ),
    .bridge_wr_data     ( bridge_wr_data ),

    .write_en           ( save_loader_wr ),
    .write_addr         ( save_loader_addr ),
    .write_data         ( save_loader_data )
);

wire        save_unloader_rd;
wire [27:0] save_unloader_addr;
wire  [7:0] save_unloader_data;

data_unloader #(
    .ADDRESS_MASK_UPPER_4   ( 4'h2 ),
    .ADDRESS_SIZE           ( 28 ),
    .READ_MEM_CLOCK_DELAY   ( 4 ),      // BRAM read latency is 1 cycle
    .INPUT_WORD_SIZE        ( 1 )
) save_data_unloader (
    .clk_74a            ( clk_74a ),
    .clk_memory         ( clk_sys ),

    .bridge_rd          ( bridge_rd ),
    .bridge_endian_little ( bridge_endian_little ),
    .bridge_addr        ( bridge_addr ),
    .bridge_rd_data     ( save_read_bridge_data ),

    .read_en            ( save_unloader_rd ),
    .read_addr          ( save_unloader_addr ),
    .read_data          ( save_unloader_data )
);

// Port A: system core access, taken over by savestates during ss_freeze
// (Dahjee A expansion RAM snapshot, lower 8 KB only, mirrors MiSTer SMS.sv).
// Port B: save load (boot) / unload (writeback).
// The Pocket OS sequences load and unload, so a simple address mux suffices.
dpram #(.widthad_a(15)) nvram_inst (
    .clock_a    ( clk_sys ),
    .address_a  ( ss_freeze ? (ss_nvram_WE ? {2'b00, ss_nvram_WA} : {2'b00, ss_nvram_A}) : nvram_a ),
    .wren_a     ( ss_freeze ? ss_nvram_WE : nvram_we ),
    .data_a     ( ss_freeze ? ss_nvram_WD : nvram_d ),
    .q_a        ( nvram_q ),

    .clock_b    ( clk_sys ),
    .address_b  ( save_loader_wr ? save_loader_addr[14:0] : save_unloader_addr[14:0] ),
    .wren_b     ( save_loader_wr ),
    .data_b     ( save_loader_data ),
    .q_b        ( save_unloader_data )
);


// ============================================================
// Section 8: Work RAM (8 KB BRAM with reset clear)
// ============================================================

wire [13:0] ram_a;
wire        ram_we;
wire  [7:0] ram_d;
wire  [7:0] ram_q;

// savestates takes the port over during ss_freeze (mirrors MiSTer SMS.sv);
// its addresses are 14-bit but only ever count to 8191 here (8 KB WRAM).
spram #(.widthad_a(13)) ram_inst (
    .clock     ( clk_sys ),
    .address   ( ss_freeze ? (ss_wram_WE ? ss_wram_WA[12:0] : ss_wram_A[12:0])
                           : (ram_clr_run ? ram_clr_addr : ram_a[12:0]) ),
    .wren      ( ss_freeze ? ss_wram_WE : (ram_clr_run | ram_we) ),
    .data      ( ss_freeze ? ss_wram_WD : (ram_clr_run ? 8'h00 : ram_d) ),
    .q         ( ram_q )
);


// ============================================================
// Section 9: Input Mapping
//   Pocket pad → SMS joypad (system inputs are active-low)
//   face_b → Button 1, face_a → Button 2
//   face_start → Pause (SMS) / Start (GG), face_select → console RESET
// ============================================================

wire [31:0] cont1_key_s;
wire [31:0] cont2_key_s;
synch_3 #(.WIDTH(32)) cont1_sync (cont1_key, cont1_key_s, clk_sys);
synch_3 #(.WIDTH(32)) cont2_sync (cont2_key, cont2_key_s, clk_sys);

wire p1_up    = cont1_key_s[0];
wire p1_down  = cont1_key_s[1];
wire p1_left  = cont1_key_s[2];
wire p1_right = cont1_key_s[3];
wire p1_b1    = cont1_key_s[5];   // face_b
wire p1_b2    = cont1_key_s[4];   // face_a
wire p1_start = cont1_key_s[15];
wire p1_sel   = cont1_key_s[14];

wire p2_up    = cont2_key_s[0];
wire p2_down  = cont2_key_s[1];
wire p2_left  = cont2_key_s[2];
wire p2_right = cont2_key_s[3];
wire p2_b1    = cont2_key_s[5];
wire p2_b2    = cont2_key_s[4];
wire p2_start = cont2_key_s[15];
wire p2_sel   = cont2_key_s[14];

wire pause_n = ~(p1_start | p2_start);          // active low at system
wire soft_reset_btn = p1_sel | p2_sel;          // SMS console RESET button


// ============================================================
// Section 10: SMS System + Video Timing
// ============================================================

wire [8:0]  vx;
wire [8:0]  vy;
wire [11:0] color;
wire        mask_column;
wire        smode_M1, smode_M2, smode_M3;
wire        HS, VS, HBlank, VBlank;
wire [15:0] audio_l, audio_r;

// ss_freeze and the gated ce inputs exactly as MiSTer SMS.sv does: pauses the
// emulated machine during a state save/load. The ce gating alone is not enough,
// system.vhd holds ~18 ss_freeze guards on paths that are not ce-qualified
// (concurrent write enables, mapper bank registers, the mapper detect counter).
// The video instance below and the sdram clkref keep their ungated ce's so
// timing keeps running.
system #(.MAX_SPPL(63), .BASE_DIR("../rtl/upstream/")) system (
    .clk_sys    ( clk_sys ),
    .ss_freeze  ( ss_freeze ),
    .ce_cpu     ( ce_cpu & ~ss_freeze ),
    .ce_vdp     ( ce_vdp & ~ss_freeze ),
    .ce_pix     ( ce_pix & ~ss_freeze ),
    .ce_sp      ( ce_sp  & ~ss_freeze ),
    .turbo      ( 1'b0 ),
    .gg         ( gg ),
    .ggres      ( ggres ),
    .systeme    ( 1'b0 ),
    .bios_en    ( bios_en ),
    .ext_bios_sel    ( 1'b0 ),
    .ext_bios_loaded ( 1'b0 ),

    .GG_EN      ( 1'b0 ),
    .GG_CODE    ( 129'd0 ),
    .GG_RESET   ( 1'b0 ),
    .GG_AVAIL   ( ),
    .gg_link_en ( link_active ),
    .gg_link_in ( {1'b1, si_sync, 5'b11111} ), // {PC6, PC5=RxD, PC4..PC0 idle}
    .gg_link_out( gg_link_out ),

    .RESET_n    ( ~reset_active ),

    .rom_rd     ( ram_rd ),
    .rom_a      ( ram_addr ),
    .rom_do     ( ram_dout ),

    .j1_up      ( ~p1_up ),
    .j1_down    ( ~p1_down ),
    .j1_left    ( ~p1_left ),
    .j1_right   ( ~p1_right ),
    .j1_tl      ( ~p1_b1 ),
    .j1_tr      ( ~p1_b2 ),
    .j1_th      ( 1'b1 ),
    .j1_start   ( 1'b0 ),
    .j1_coin    ( 1'b0 ),
    .j1_a3      ( 1'b0 ),

    .j2_up      ( ~p2_up ),
    .j2_down    ( ~p2_down ),
    .j2_left    ( ~p2_left ),
    .j2_right   ( ~p2_right ),
    .j2_tl      ( ~p2_b1 ),
    .j2_tr      ( ~p2_b2 ),
    .j2_th      ( 1'b1 ),
    .j2_start   ( 1'b0 ),
    .j2_coin    ( 1'b0 ),
    .j2_a3      ( 1'b0 ),

    .pause      ( pause_n ),
    .soft_reset ( soft_reset_btn ),

    .E0Type     ( 2'b00 ),
    .E1Use      ( 1'b0 ),
    .E2Use      ( 1'b0 ),
    .E0         ( 8'h00 ),
    .F2         ( 8'h00 ),
    .F3         ( 8'h00 ),

    .has_paddle ( 1'b0 ),
    .has_pedal  ( 1'b0 ),
    .paddle     ( 8'h00 ),
    .paddle2    ( 8'h00 ),
    .pedal      ( 8'h00 ),
    .sc3000_en  ( 1'b0 ),
    .sc_multicart_en ( 1'b0 ),
    .sc_megacart_en  ( 1'b0 ),
    .sc_cart_ram     ( 2'b00 ),
    .sk1100_en       ( 1'b0 ),
    .sk1100_row_sel  ( ),
    .sk1100_row_data ( 12'hFFF ),

    .j1_tr_out  ( ),
    .j1_th_out  ( ),
    .j2_tr_out  ( ),
    .j2_th_out  ( ),

    .x          ( vx ),
    .y          ( vy ),
    .color      ( color ),
    .palettemode( palettemode ),
    .tms_palette( tms_palette_s ),
    .mask_column( mask_column ),
    .black_column( blank_border_s ),
    .smode_M1   ( smode_M1 ),
    .smode_M2   ( smode_M2 ),
    .smode_M3   ( smode_M3 ),
    .ysj_quirk  ( ysj_quirk ),
    .pal        ( pal_s ),
    .region     ( region_s ),
    .mapper_lock          ( mapper_sel_s == 3'd1 ),  // Sega
    .mapper_codies_force  ( mapper_sel_s == 3'd2 ),  // Codemasters
    .mapper_zemina_force  ( mapper_sel_s == 3'd3 ),  // Korean (Zemina/Nemesis)
    .mapper_linear_force  ( mapper_sel_s == 3'd4 ),  // linear (no mapper)
    .mapper_dahjee_a_force( mapper_sel_s == 3'd5 ),  // Dahjee Type A
    .vdp_enables( 2'b00 ),
    .psg_enables( 2'b00 ),

    .audioL     ( audio_l ),
    .audioR     ( audio_r ),
    .fm_ena     ( ~fm_disable_s | gg ),

    .dbr        ( dbr ),
    .sp64       ( sprites_all_s ),

    .ram_a      ( ram_a ),
    .ram_we     ( ram_we ),
    .ram_d      ( ram_d ),
    .ram_q      ( ram_q ),

    .nvram_a    ( nvram_a ),
    .nvram_we   ( nvram_we ),
    .nvram_d    ( nvram_d ),
    .nvram_q    ( nvram_q ),

    .encrypt    ( 2'b00 ),
    .key_a      ( ),
    .key_d      ( 8'h00 ),

    .ROMCL      ( clk_sys ),
    .ROMAD      ( romwr_a ),
    .ROMDT      ( romwr_d ),
    .ROMEN      ( rom_byte_wr ),
    .BIOSWEN    ( 1'b0 ),

    .z80_reg_out ( ss_z80_reg ),
    .z80_dir     ( ss_z80_dir ),
    .z80_set     ( ss_z80_set ),
    .vdp_regs_out( ss_vdp_regs ),
    .vdp_regs_in ( ss_vdp_regs_in ),
    .vdp_regs_set( ss_vdp_regs_set ),
    .vdp_cram_out( ss_vdp_cram ),
    .ss_cram_wr  ( ss_cram_wr ),
    .ss_cram_A   ( ss_cram_A ),
    .ss_cram_D   ( ss_cram_D ),
    .ss_vram_en  ( ss_vram_en ),
    .ss_vram_A   ( ss_vram_A ),
    .ss_vram_D   ( ss_vram_D ),
    .ss_vram_WE  ( ss_vram_WE ),
    .ss_vram_WA  ( ss_vram_WA ),
    .ss_vram_WD  ( ss_vram_WD ),
    .psg_out     ( ss_psg_out ),
    .psg_in      ( ss_psg_in ),
    .psg_set     ( ss_psg_set ),
    .mapper_out  ( ss_mapper_out ),
    .mapper_in   ( ss_mapper_in ),
    .mapper_set  ( ss_mapper_set ),
    .io_state_out( ss_io_out ),
    .io_state_in ( ss_io_in ),
    .io_state_set( ss_io_set ),
    .z80_m1_n    ( ss_z80_m1_n ),
    .z80_mreq_n  ( ss_z80_mreq_n ),
    .z80_iset    ( ss_z80_iset )
);

video video (
    .clk        ( clk_sys ),
    .ce_pix     ( ce_pix ),
    .pal        ( pal_machine ),
    .ggres      ( ggres ),
    .border     ( 1'b0 ),
    .mask_column( mask_column ),
    .cut_mask   ( 1'b0 ),
    .smode_M1   ( smode_M1 ),
    .smode_M2   ( smode_M2 ),
    .smode_M3   ( smode_M3 ),
    .smode_M4   ( 1'b0 ),
    .video_state_out( ss_video_state_out ),
    .video_state_in ( ss_video_state_in ),
    .video_state_set( 1'b0 ),   // MiSTer ties this off too: raster is realigned by waiting, not restored
    .x          ( vx ),
    .y          ( vy ),
    .hsync      ( HS ),
    .vsync      ( VS ),
    .hblank     ( HBlank ),
    .vblank     ( VBlank )
);


// ============================================================
// Section 10b: Savestates (sleep/wake)
//   MiSTer savestates.sv engine + APF bridge controller. The engine's
//   DDRAM-style bus is served by a 64 KB BRAM inside the controller
//   instead of MiSTer's DDR3. One slot (slot 0), cart mode only.
// ============================================================

savestates savestates_inst (
    .clk             ( clk_sys ),
    .reset_n         ( ~reset_active ),
    .ss_save         ( ss_save ),
    .ss_load         ( ss_load ),
    .ss_slot         ( 2'd0 ),
    .ss_bios_mode    ( bios_en & ~dbr ),   // MiSTer: bios_en & ~dbr
    .ss_game_id      ( ss_game_id ),       // ROM signature: reject cross-ROM loads
    .ss_freeze       ( ss_freeze ),
    .vblank          ( VBlank ),
    .x               ( vx ),
    // Z80
    .z80_reg         ( ss_z80_reg ),
    .z80_dir         ( ss_z80_dir ),
    .z80_set         ( ss_z80_set ),
    .z80_m1_n        ( ss_z80_m1_n ),
    .z80_mreq_n      ( ss_z80_mreq_n ),
    .z80_iset        ( ss_z80_iset ),
    .cpu_ce          ( ce_cpu ),        // raw, ungated by ss_freeze
    .vdp_ce          ( ce_vdp ),
    .pix_ce          ( ce_pix ),
    .sp_ce           ( ce_sp ),
    // VDP registers
    .vdp_regs        ( ss_vdp_regs ),
    .vdp_regs_in     ( ss_vdp_regs_in ),
    .vdp_regs_set    ( ss_vdp_regs_set ),
    // CRAM
    .cram_out        ( ss_vdp_cram ),
    .cram_A          ( ss_cram_A ),
    .cram_D          ( ss_cram_D ),
    .cram_wr         ( ss_cram_wr ),
    // VRAM DMA
    .vram_en         ( ss_vram_en ),
    .vram_A          ( ss_vram_A ),
    .vram_D          ( ss_vram_D ),
    .vram_WE         ( ss_vram_WE ),
    .vram_WA         ( ss_vram_WA ),
    .vram_WD         ( ss_vram_WD ),
    // PSG
    .psg_out         ( ss_psg_out ),
    .psg_in          ( ss_psg_in ),
    .psg_set         ( ss_psg_set ),
    // Mapper
    .mapper_out      ( ss_mapper_out ),
    .mapper_in       ( ss_mapper_in ),
    .mapper_set      ( ss_mapper_set ),
    .io_out          ( ss_io_out ),
    .io_in           ( ss_io_in ),
    .io_set          ( ss_io_set ),
    .video_state_out ( ss_video_state_out ),
    .video_state_in  ( ss_video_state_in ),
    .video_state_set ( ss_video_state_set ),
    // WRAM DMA (ram_inst port, muxed in Section 8)
    .wram_A          ( ss_wram_A ),
    .wram_D          ( ram_q ),
    .wram_WE         ( ss_wram_WE ),
    .wram_WA         ( ss_wram_WA ),
    .wram_WD         ( ss_wram_WD ),
    // NVRAM DMA (Dahjee A expansion RAM, nvram_inst port A, muxed in Section 7)
    .nvram_A         ( ss_nvram_A ),
    .nvram_D         ( nvram_q ),
    .nvram_WE        ( ss_nvram_WE ),
    .nvram_WA        ( ss_nvram_WA ),
    .nvram_WD        ( ss_nvram_WD ),
    // DDRAM-style bus → BRAM shim in the controller
    .DDRAM_ADDR      ( ss_ddram_addr ),
    .DDRAM_DIN       ( ss_ddram_din ),
    .DDRAM_BE        ( ss_ddram_be ),
    .DDRAM_WE        ( ss_ddram_we ),
    .DDRAM_DOUT      ( ss_ddram_dout ),
    .DDRAM_DOUT_READY( ss_ddram_dout_ready ),
    .DDRAM_RD        ( ss_ddram_rd ),
    .DDRAM_BURSTCNT  ( ss_ddram_burstcnt ),
    .DDRAM_BUSY      ( ss_ddram_busy )
);

savestate_controller savestate_controller (
    .clk_74a    ( clk_74a ),
    .clk_sys    ( clk_sys ),

    .bridge_wr      ( bridge_wr ),
    .bridge_addr    ( bridge_addr ),
    .bridge_wr_data ( bridge_wr_data ),
    .ss_bridge_rd_data ( ss_bridge_rd_data ),

    .savestate_start        ( savestate_start ),
    .savestate_start_ack_s  ( savestate_start_ack ),
    .savestate_start_busy_s ( savestate_start_busy ),
    .savestate_start_ok_s   ( savestate_start_ok ),
    .savestate_start_err_s  ( savestate_start_err ),

    .savestate_load         ( savestate_load ),
    .savestate_load_ack_s   ( savestate_load_ack ),
    .savestate_load_busy_s  ( savestate_load_busy ),
    .savestate_load_ok_s    ( savestate_load_ok ),
    .savestate_load_err_s   ( savestate_load_err ),

    .allow_ss   ( allow_ss ),
    .ss_save    ( ss_save ),
    .ss_load    ( ss_load ),
    .ss_freeze  ( ss_freeze ),

    .DDRAM_ADDR      ( ss_ddram_addr ),
    .DDRAM_DIN       ( ss_ddram_din ),
    .DDRAM_BE        ( ss_ddram_be ),
    .DDRAM_WE        ( ss_ddram_we ),
    .DDRAM_DOUT      ( ss_ddram_dout ),
    .DDRAM_DOUT_READY( ss_ddram_dout_ready ),
    .DDRAM_RD        ( ss_ddram_rd ),
    .DDRAM_BURSTCNT  ( ss_ddram_burstcnt ),
    .DDRAM_BUSY      ( ss_ddram_busy )
);


// ============================================================
// Section 11: Video Output (raster, no framebuffer)
// ============================================================

assign video_rgb_clock    = clk_vid;
assign video_rgb_clock_90 = clk_vid_90;

video_sms video_out (
    .clk_sys    ( clk_sys ),
    .clk_vid    ( clk_vid ),
    .reset      ( ~pll_core_locked ),

    .color      ( color ),
    .hs         ( HS ),
    .vs         ( VS ),
    .hblank     ( HBlank ),
    .vblank     ( VBlank ),

    .ggres      ( ggres ),
    .smode_M1   ( smode_M1 ),
    .smode_M2   ( smode_M2 ),
    .smode_M3   ( smode_M3 ),

    .video_rgb  ( video_rgb ),
    .video_de   ( video_de ),
    .video_hs   ( video_hs ),
    .video_vs   ( video_vs ),
    .video_skip ( video_skip )
);


// ============================================================
// Section 12: Audio Output
// ============================================================

audio_mixer #(
    .DW     ( 16 ),
    .STEREO ( 1 )
) audio_out (
    .clk_74b    ( clk_74a ),
    .clk_audio  ( clk_sys ),
    .reset      ( reset_active ),
    .vol_att    ( 4'd0 ),
    .mix        ( 2'd1 ),              // 25% L/R crossfeed (MiSTer AUDIO_MIX = 1)
    .is_signed  ( 1'b1 ),
    .core_l     ( audio_l ),
    .core_r     ( audio_r ),
    .audio_mclk ( audio_mclk ),
    .audio_lrck ( audio_lrck ),
    .audio_dac  ( audio_dac )
);

endmodule
