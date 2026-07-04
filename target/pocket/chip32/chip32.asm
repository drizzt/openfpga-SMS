// Chip32 loader for the SMS core
//
// Detects the system from the cartridge file extension and writes the mode
// register before streaming the ROM:
//   .sms -> mode 0 (Master System, default)
//   .gg  -> mode 1 (Game Gear)
//   .sg  -> mode 2 (SG-1000)
//
// Structure adapted from agg23/openfpga-wonderswan.

architecture chip32.vm
output "chip32.bin", create

// scratch area in the last 1K of the 8K chip32 memory
constant rambuf = 0x1b00

constant cart_dataslot = 1
constant save_dataslot = 2

// core_top.sv bridge registers
constant download_addr = 0x0    // downloading flag (reset envelope)
constant mode_addr = 0x4        // 0=sms, 1=gg, 2=sg1000

// Host init command
constant host_init = 0x4002

// Error vector (0x0)
jp error_handler

// Init vector (0x2)
// Choose core (bitstream 0)
ld r0,#0
core r0

// Detect system from cartridge file extension
ld r1,#cart_dataslot
ld r2,#rambuf
getext r1,r2
ld r1,#ext_gg
test r1,r2
jp z,is_gg
ld r1,#ext_sg
test r1,r2
jp z,is_sg

ld r3,#0                    // .sms (or anything else): Master System
jp set_mode

is_gg:
ld r3,#1
jp set_mode

is_sg:
ld r3,#2

set_mode:
ld r1,#mode_addr
pmpw r1,r3                  // write mode register before loading the ROM

// Load cartridge with the download envelope asserted
ld r1,#download_addr
ld r2,#1
pmpw r1,r2                  // downloading = 1 (core held in reset)

ld r3,#cart_dataslot
ld r14,#rom_err_msg
loadf r3                    // stream cart -> bridge 0x10000000 -> SDRAM
jp nz,print_error_and_exit

ld r1,#download_addr
ld r2,#0
pmpw r1,r2                  // downloading = 0 (latches cart size / header skip)

// Load save data if present (missing file is not an error)
ld r3,#save_dataslot
loadf r3

// Start the core
ld r0,#host_init
host r0,r0

exit 0

// Error handling
error_handler:
ld r14,#generic_err_msg

print_error_and_exit:
printf r14
exit 1

ext_gg:
db "GG",0

ext_sg:
db "SG",0

rom_err_msg:
db "Could not load ROM",0

generic_err_msg:
db "Error",0
