#
# user core constraints
#
# put your clock groups in here as well as any net assignments
#

# ============================================================
# SDRAM Timing Constraints
# ============================================================
# SDRAM: AS4C32M16MSA-6BIN (512 Mbit, 166 MHz max, -6 speed grade)
# dram_clk is DDR-forwarded from PLL outclk_1 (180 deg phase, 9312 ps).
#
# Write path (FPGA -> SDRAM):
#   tDS = 1.5 ns  (data/address/command setup to CLK)
#   tDH = 0.8 ns  (data/address/command hold after CLK)
#
# Read path (SDRAM -> FPGA), CAS latency 2:
#   tAC = 6.0 ns  (access time from CLK, max)
#   tOH = 2.5 ns  (output hold from CLK, min)

# Generated clock on SDRAM CLK output pin
# IMPORTANT: This must be defined BEFORE set_clock_groups below,
# so the fitter knows about sdram_clk during timing-driven optimization.
create_generated_clock -name sdram_clk \
  -source [get_pins {ic|mp1|mf_pllbase_inst|altera_pll_i|cyclonev_pll|counter[1].output_counter|divclk}] \
  [get_ports {dram_clk}]

# Clock groups: all four altera_pll outputs come from the same VCO and are
# phase-related, so they all belong in the SAME group. STA is signed off at
# the NTSC power-up frequencies; the PAL reconfig (53.203424 MHz) is ~0.9%
# slower, so NTSC is the worst case. The altera_pll is subtype "Reconfigurable"
# (counter[N].output_counter paths, not general[N].gpll~ like the audio PLL):
#  - counter[0] = clk_sys 53.693175 MHz
#  - counter[1] = SDRAM clock (DDR-forwarded to dram_clk)
#  - counter[2] = clk_vid 5.3693175 MHz (= clk_sys/10, raster output samples
#    the clk_sys-domain VDP color/sync directly, so this crossing is timed)
#  - counter[3] = clk_vid 90 deg (DDR video output)
set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk \
          ic|mp1|mf_pllbase_inst|altera_pll_i|cyclonev_pll|counter[1].output_counter|divclk \
          sdram_clk \
          ic|mp1|mf_pllbase_inst|altera_pll_i|cyclonev_pll|counter[2].output_counter|divclk \
          ic|mp1|mf_pllbase_inst|altera_pll_i|cyclonev_pll|counter[3].output_counter|divclk } \
 -group { ic|audio_out|audio_pll|mf_audio_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|audio_out|audio_pll|mf_audio_pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk }

derive_clock_uncertainty

# Write path: output delay for all SDRAM outputs relative to sdram_clk
set_output_delay -clock sdram_clk -max 1.5 \
  [get_ports {dram_a[*] dram_ba[*] dram_dq[*] dram_dqm[*] dram_ras_n dram_cas_n dram_we_n dram_cke}]
set_output_delay -clock sdram_clk -min -0.8 \
  [get_ports {dram_a[*] dram_ba[*] dram_dq[*] dram_dqm[*] dram_ras_n dram_cas_n dram_we_n dram_cke}]

# Read path: input delay for DQ relative to sdram_clk
# tAC = 6.0 ns max (access time from CLK, CL=2)
# tOH = 2.5 ns min (output hold from CLK)
set_input_delay -clock sdram_clk -max 6.0 [get_ports {dram_dq[*]}]
set_input_delay -clock sdram_clk -min 2.5 [get_ports {dram_dq[*]}]

# Multicycle path for SDRAM read capture:
# sd_dat is loaded only at q == STATE_READY, three clk_sys cycles after the
# READ command was issued, so the single-cycle 9.3 ns launch->capture
# relationship STA assumes never happens in the RTL. Relax setup to the
# 2nd capture edge (27.9 ns) like the GBA port does; the actual sampling
# alignment is fixed by the controller state machine (MiSTer-proven at
# this exact frequency and 180-degree clock phase).
set_multicycle_path -setup -from [get_clocks {sdram_clk}] \
  -to [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] 2
set_multicycle_path -hold -from [get_clocks {sdram_clk}] \
  -to [get_clocks {ic|mp1|mf_pllbase_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] 1

# Multicycle path for PLL reconfiguration DPRIO writes:
# On a NTSC/PAL switch the reconfig core streams the new fractional-K word into
# the altera_pll over many clk_74a cycles via the DPRIO (avmm_dprio_writedata)
# interface, with the write data held stable and the PLL gated by WAIT_FOR_LOCK.
# The single-cycle 13.5 ns launch->capture relationship STA assumes therefore
# never happens: the reconfig sequence is microseconds long and config-time only
# (no gameplay path). Relax setup to the 2nd edge, exactly like the SDRAM capture
# above. Scoped -from the reconfig core -to the altera_pll, so it covers ONLY the
# reconfig writes and never the PLL clock outputs.
set_multicycle_path -setup -end 2 \
  -from [get_registers {*altera_pll_reconfig_core*}] \
  -to   [get_registers {*mf_pllbase_inst*}]
set_multicycle_path -hold -end 1 \
  -from [get_registers {*altera_pll_reconfig_core*}] \
  -to   [get_registers {*mf_pllbase_inst*}]

# Non-SDRAM top-level I/O timing coverage:
# These APF/platform interfaces are not signed off with external setup/hold
# delays here. They are either protocol/wait-state timed, source-synchronous
# to fixed platform wiring, or handled by the APF bridge logic. Marking them
# false path keeps TimeQuest's "fully constrained" check focused on the paths
# this core actually constrains instead of reporting intentionally unmanaged
# board-level I/O.
set_false_path -from [get_ports { \
  bridge_1wire bridge_spimiso bridge_spimosi bridge_spiss \
  cram0_dq[*] \
  port_tran_sck port_tran_sd port_tran_si \
}]

set_false_path -to [get_ports { \
  bridge_1wire bridge_spimiso bridge_spimosi \
  cram0_a[*] cram0_adv_n cram0_ce0_n cram0_ce1_n cram0_clk cram0_cre \
  cram0_dq[*] cram0_lb_n cram0_oe_n cram0_ub_n cram0_we_n \
  port_tran_sck port_tran_sck_dir port_tran_sd port_tran_sd_dir port_tran_so \
  scal_auddac scal_audlrck scal_audmclk scal_clk scal_de scal_hs scal_skip \
  scal_vid[*] scal_vs \
}]
