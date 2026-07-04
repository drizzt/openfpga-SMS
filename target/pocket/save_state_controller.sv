//
// save_state_controller.sv — APF save-state bridge for the SMS core
//
// Glues the Pocket OS save-state protocol (host commands 0x00A0/0x00A4,
// blob exchanged over the bridge at 0x4xxxxxxx) to MiSTer's pure-hardware
// savestates.sv engine, which expects a MiSTer DDRAM-style 64-bit bus.
//
// The whole state slot is 64 KB (savestates.sv slot 0), so instead of the
// SDRAM staging the GBA reference port needs for its ~389 KB state, the
// slot lives in a dual-clock BRAM buffer:
//
//   savestates.sv (clk_sys) ←DDRAM shim→ [64K BRAM] ←→ bridge (clk_74a)
//
// savestates.sv keeps the MiSTer slot base address (29'h07C00000); only
// the word-offset bits [12:0] address the buffer, the base is ignored.
// Slot 0 / cart mode only (ss_slot and ss_bios_mode are tied off in
// core_top.sv), so DDRAM_ADDR[28:13] never varies.
//

module save_state_controller (
    input  wire        clk_74a,
    input  wire        clk_sys,

    // APF bridge (clk_74a) — savestate blob window at 0x4xxxxxxx
    input  wire        bridge_wr,
    input  wire [31:0] bridge_addr,
    input  wire [31:0] bridge_wr_data,
    output reg  [31:0] ss_bridge_rd_data,

    // APF save-state handshake (core_bridge_cmd, clk_74a domain)
    input  wire        savestate_start,
    output wire        savestate_start_ack_s,
    output wire        savestate_start_busy_s,
    output wire        savestate_start_ok_s,
    output wire        savestate_start_err_s,

    input  wire        savestate_load,
    output wire        savestate_load_ack_s,
    output wire        savestate_load_busy_s,
    output wire        savestate_load_ok_s,
    output wire        savestate_load_err_s,

    // Core-side control (clk_sys)
    input  wire        allow_ss,        // state save/load currently permitted
    output reg         ss_save,         // one-cycle pulse to savestates.sv
    output reg         ss_load,         // one-cycle pulse to savestates.sv
    input  wire        ss_freeze,

    // DDRAM-style bus from savestates.sv (clk_sys)
    input  wire [28:0] DDRAM_ADDR,
    input  wire [63:0] DDRAM_DIN,
    input  wire  [7:0] DDRAM_BE,
    input  wire        DDRAM_WE,
    output wire [63:0] DDRAM_DOUT,
    output reg         DDRAM_DOUT_READY,
    input  wire        DDRAM_RD,
    input  wire  [7:0] DDRAM_BURSTCNT,  // always 8'd1 in savestates.sv — ignored
    output wire        DDRAM_BUSY
);

// Byte order convention copied from the working GBA/GBC reference ports:
// every 32-bit word is byte-swapped between the engine and the bridge in
// BOTH directions (GBA ingests bridge writes raw into its FIFO but swaps
// at the engine handoff; our buffer feeds the engine directly, so the
// swap happens at the port-B write). Symmetric, so save→load round-trips.
function automatic [31:0] bswap(input [31:0] d);
    bswap = {d[7:0], d[15:8], d[23:16], d[31:24]};
endfunction

// ============================================================
// 64 KB state buffer (16K × 32, true dual clock)
//   Port A: DDRAM shim (clk_sys), 64-bit words as two halves,
//           low 32 bits at even address (LSW first over the bridge)
//   Port B: APF bridge (clk_74a)
// ============================================================

wire [13:0] buf_addr_a;
wire        buf_wren_a;
wire [31:0] buf_data_a;
wire [31:0] buf_q_a;
wire [31:0] buf_q_b;

// Gate on the full 64 KB window, not just the 0x4 nibble: the NES reference
// notes the host may emit extra trailing data past the blob on load
// ("discard on loading", maxloadsize = size + 0x1000 there). Such writes
// land at 0x4001xxxx and must be discarded — with the +1 below they would
// otherwise alias onto buffer words 1-2 and clobber the magic.
wire        bridge_ss_wr = bridge_wr && (bridge_addr[31:28] == 4'h4)
                                     && (bridge_addr[27:16] == 12'h0);

// Host write skew (measured in silicon, instrumentation round 7): on load
// the OS streams the blob skipping its first 32-bit word — the write at
// word address j carries blob word j+1 ((0,w1), (1,w2), ...), while saves
// read the window faithfully from word 0. Compensate with +1 on the write
// address. Blob word 0 is the engine's {size, change_det} header half,
// which the load FSM never reads (it starts at slot qword 1), so the lost
// word — and the last write wrapping to buffer word 0 with junk — are both
// harmless. Reference cores never see this: they ingest blob writes
// through FIFOs and ignore the address entirely.
dpram #(.widthad_a(14), .width_a(32)) ss_buffer (
    .clock_a    ( clk_sys ),
    .address_a  ( buf_addr_a ),
    .wren_a     ( buf_wren_a ),
    .data_a     ( buf_data_a ),
    .q_a        ( buf_q_a ),

    .clock_b    ( clk_74a ),
    .address_b  ( bridge_ss_wr ? bridge_addr[15:2] + 14'd1
                                : bridge_addr[15:2] ),
    .wren_b     ( bridge_ss_wr ),
    .data_b     ( bswap(bridge_wr_data) ),
    .q_b        ( buf_q_b )
);

// Blob stream tracking (clk_74a), GBA staging_complete equivalent: a load
// may only start once a full 64 KB stream (16384 word writes) has landed,
// whichever side of the load command the OS streams it on. The OS streams
// every blob ascending from word 0, so a write there is the deterministic
// start-of-stream marker — no idle timer, so mid-stream SD stalls of any
// length cannot split the count. "complete" persists after a stream ends
// and clears when the next one begins.
reg [14:0] blob_wr_total = 0;     // saturating; bit 14 set at 16384 writes
reg        blob_complete = 0;
always @(posedge clk_74a) begin
    if (bridge_ss_wr) begin
        if (bridge_addr[15:2] == 14'd0) begin
            blob_complete <= 0;
            blob_wr_total <= 15'd1;
        end else if (!blob_wr_total[14]) begin
            blob_wr_total <= blob_wr_total + 1'd1;
            if (blob_wr_total == 15'd16383) blob_complete <= 1;
        end
    end
end

wire blob_complete_s;
synch_3 blob_complete_sync (blob_complete, blob_complete_s, clk_sys);

// Bridge reads tolerate a few cycles of latency, so one output register
// for timing is fine.
always @(posedge clk_74a) begin
    ss_bridge_rd_data <= bswap(buf_q_b);
end

// ============================================================
// DDRAM shim (clk_sys)
//
// savestates.sv only ever issues single-beat transactions, asserts WE/RD
// as registered one-cycle pulses gated on !BUSY, and keeps exactly one
// read outstanding (so reads and writes never overlap with each other).
// BE is only ever 8'h0F (header control word) or 8'hFF — 32-bit halves,
// never sub-word, so per-half write enables suffice.
// ============================================================

// Write: low half this cycle, high half (if enabled) the next one.
reg        wr_high_pending = 0;
reg [12:0] wr_addr_hold;
reg [31:0] wr_data_hold;

// Read: addr+0 presented on the RD cycle, low word latched the cycle
// after, DOUT_READY pulsed the cycle after that with the high word live
// on q_a.
reg        rd_pending = 0;
reg [12:0] rd_addr_hold;
reg [31:0] rd_low_latch;
reg [12:0] load_read_count = 0;     // saturating; total reads on a good load ≥ 3087

assign DDRAM_BUSY = DDRAM_WE | wr_high_pending;

assign buf_addr_a = DDRAM_WE        ? {DDRAM_ADDR[12:0], 1'b0} :
                    wr_high_pending ? {wr_addr_hold, 1'b1} :
                    rd_pending      ? {rd_addr_hold, 1'b1} :
                                      {DDRAM_ADDR[12:0], 1'b0};
assign buf_wren_a = (DDRAM_WE & |DDRAM_BE[3:0]) | wr_high_pending;
assign buf_data_a = DDRAM_WE        ? DDRAM_DIN[31:0] :
                                      wr_data_hold;

assign DDRAM_DOUT = {buf_q_a, rd_low_latch};

always @(posedge clk_sys) begin
    DDRAM_DOUT_READY <= 0;

    // BE=8'h0F skips the high half, preserving the upper 32 bits of the
    // word — matches DDR byte-enable semantics.
    wr_high_pending <= DDRAM_WE & |DDRAM_BE[7:4];
    if (DDRAM_WE) begin
        wr_addr_hold <= DDRAM_ADDR[12:0];
        wr_data_hold <= DDRAM_DIN[63:32];
    end

    if (DDRAM_RD) begin
        rd_addr_hold <= DDRAM_ADDR[12:0];
        rd_pending   <= 1;
        if (~&load_read_count) load_read_count <= load_read_count + 1'd1;
    end else if (rd_pending) begin
        rd_low_latch     <= buf_q_a;
        DDRAM_DOUT_READY <= 1;
        rd_pending       <= 0;
    end

    if (ss_load) load_read_count <= 0;
end

// ============================================================
// APF handshake FSM (clk_sys)
//
// savestates.sv has no done/ok/err outputs: completion is the fall of
// ss_freeze. A save does zero DDRAM reads, so freeze-fall after a save is
// unambiguous success. A load that rejects the magic word does exactly
// one read before unfreezing; a successful load does ≥ 3087, so the read
// counter distinguishes ok from err.
// ============================================================

// MiSTer's slot magic check: a successful load reads
// 1 hdr + 4 Z80 + 2 VDP + 6 CRAM + 1 PSG + 1 mapper + 2048 VRAM + 1024 WRAM
// (+1024 Dahjee NVRAM) words.
localparam [12:0] LOAD_MIN_READS = 13'd3087;

localparam [2:0] ST_IDLE             = 3'd0,
                 ST_SAVE_WAIT_FREEZE = 3'd1,
                 ST_SAVE_WAIT_DONE   = 3'd2,
                 ST_LOAD_WAIT_ALLOW  = 3'd3,
                 ST_LOAD_WAIT_FREEZE = 3'd4,
                 ST_LOAD_WAIT_DONE   = 3'd5;

reg [2:0]  state = ST_IDLE;
// savestates.sv can only enter freeze at a clean Z80 instruction boundary,
// which never comes if the request was mis-gated — bail out after ~2.5 s.
reg [26:0] freeze_timeout;
// On wake the OS may issue the load command while the ROM download/reset
// is still in flight; hold busy and wait for allow_ss instead of erroring
// (~10 s @ 53.69 MHz covers any cart download).
reg [28:0] allow_timeout;

wire savestate_start_s, savestate_load_s;
synch_3 #(.WIDTH(2)) ss_req_sync (
    {savestate_start, savestate_load},
    {savestate_start_s, savestate_load_s},
    clk_sys
);

reg prev_start_s = 0, prev_load_s = 0;

reg savestate_start_ack = 0, savestate_start_busy = 0;
reg savestate_start_ok = 0,  savestate_start_err = 0;
reg savestate_load_ack = 0,  savestate_load_busy = 0;
reg savestate_load_ok = 0,   savestate_load_err = 0;

synch_3 #(.WIDTH(8)) ss_status_sync (
    {savestate_start_ack,   savestate_start_busy,
     savestate_start_ok,    savestate_start_err,
     savestate_load_ack,    savestate_load_busy,
     savestate_load_ok,     savestate_load_err},
    {savestate_start_ack_s, savestate_start_busy_s,
     savestate_start_ok_s,  savestate_start_err_s,
     savestate_load_ack_s,  savestate_load_busy_s,
     savestate_load_ok_s,   savestate_load_err_s},
    clk_74a
);

always @(posedge clk_sys) begin
    ss_save <= 0;
    ss_load <= 0;

    prev_start_s <= savestate_start_s;
    prev_load_s  <= savestate_load_s;

    // Hold ack until the (synchronized) request deasserts, so the host —
    // which keeps the request high until it sees ack — can't miss it.
    if (~savestate_start_s) savestate_start_ack <= 0;
    if (~savestate_load_s)  savestate_load_ack  <= 0;

    case (state)
    ST_IDLE: begin
        if (savestate_start_s & ~prev_start_s) begin
            savestate_start_ack <= 1;
            savestate_start_ok  <= 0;
            savestate_start_err <= 0;
            if (allow_ss) begin
                savestate_start_busy <= 1;
                ss_save        <= 1;
                freeze_timeout <= 0;
                state          <= ST_SAVE_WAIT_FREEZE;
            end else begin
                savestate_start_err <= 1;
            end
        end else if (savestate_load_s & ~prev_load_s) begin
            savestate_load_ack  <= 1;
            savestate_load_ok   <= 0;
            savestate_load_err  <= 0;
            savestate_load_busy <= 1;
            allow_timeout       <= 0;
            state               <= ST_LOAD_WAIT_ALLOW;
        end
    end

    ST_LOAD_WAIT_ALLOW: begin
        allow_timeout <= allow_timeout + 1'd1;
        if (allow_ss && blob_complete_s) begin
            ss_load        <= 1;
            freeze_timeout <= 0;
            state          <= ST_LOAD_WAIT_FREEZE;
        end else if (&allow_timeout) begin
            savestate_load_busy <= 0;
            savestate_load_err  <= 1;
            state <= ST_IDLE;
        end
    end

    ST_SAVE_WAIT_FREEZE: begin
        freeze_timeout <= freeze_timeout + 1'd1;
        if (ss_freeze) begin
            state <= ST_SAVE_WAIT_DONE;
        end else if (&freeze_timeout) begin
            savestate_start_busy <= 0;
            savestate_start_err  <= 1;
            state <= ST_IDLE;
        end
    end

    ST_SAVE_WAIT_DONE: begin
        if (~ss_freeze) begin
            savestate_start_busy <= 0;
            savestate_start_ok   <= 1;
            state <= ST_IDLE;
        end
    end

    ST_LOAD_WAIT_FREEZE: begin
        freeze_timeout <= freeze_timeout + 1'd1;
        if (ss_freeze) begin
            state <= ST_LOAD_WAIT_DONE;
        end else if (&freeze_timeout) begin
            savestate_load_busy <= 0;
            savestate_load_err  <= 1;
            state <= ST_IDLE;
        end
    end

    ST_LOAD_WAIT_DONE: begin
        if (~ss_freeze) begin
            savestate_load_busy <= 0;
            if (load_read_count >= LOAD_MIN_READS) savestate_load_ok  <= 1;
            else savestate_load_err <= 1;
            state <= ST_IDLE;
        end
    end

    default: state <= ST_IDLE;
    endcase
end

endmodule
