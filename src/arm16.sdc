# arm16 timing constraints (docs/spec.md section 12, after TinyQV): 65% of the period as external delay
# on the Pmod-facing pins, 20% on the memory clock output, extra uncertainty on the paths that cross
# between the rising and the falling edge (the SCK copy flop). Structure follows LibreLane's base.sdc.
set clock_port $::env(CLOCK_PORT)
create_clock [get_ports $clock_port] -name $clock_port -period $::env(CLOCK_PERIOD)
set clocks [get_clocks $clock_port]
set period $::env(CLOCK_PERIOD)

set io_max [expr $period * 0.65]
set io_min [expr $period * 0.20]
set sck_max [expr $period * 0.20]

set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
if { [info exists ::env(MAX_TRANSITION_CONSTRAINT)] } {
    set_max_transition $::env(MAX_TRANSITION_CONSTRAINT) [current_design]
}
if { [info exists ::env(MAX_CAPACITANCE_CONSTRAINT)] } {
    set_max_capacitance $::env(MAX_CAPACITANCE_CONSTRAINT) [current_design]
}

set clk_input [get_port $clock_port]
set clk_indx [lsearch [all_inputs] $clk_input]
set all_inputs_wo_clk [lreplace [all_inputs] $clk_indx $clk_indx ""]

set_input_delay -max $io_max -clock $clocks $all_inputs_wo_clk
set_input_delay -min $io_min -clock $clocks $all_inputs_wo_clk
set_output_delay -max $io_max -clock $clocks [all_outputs]
set_output_delay -min 1.0 -clock $clocks [all_outputs]
# the memory clock pin: the chip needs it early, the 20% budget of the TinyQV constraints
set_output_delay -max $sck_max -clock $clocks [get_ports {uio_out[3]}]

if { ![info exists ::env(SYNTH_CLK_DRIVING_CELL)] } {
    set ::env(SYNTH_CLK_DRIVING_CELL) $::env(SYNTH_DRIVING_CELL)
}
set_driving_cell \
    -lib_cell [lindex [split $::env(SYNTH_DRIVING_CELL) "/"] 0] \
    -pin [lindex [split $::env(SYNTH_DRIVING_CELL) "/"] 1] \
    $all_inputs_wo_clk
set_driving_cell \
    -lib_cell [lindex [split $::env(SYNTH_CLK_DRIVING_CELL) "/"] 0] \
    -pin [lindex [split $::env(SYNTH_CLK_DRIVING_CELL) "/"] 1] \
    $clk_input

set cap_load [expr $::env(OUTPUT_CAP_LOAD) / 1000.0]
set_load $cap_load [all_outputs]

set_clock_uncertainty $::env(CLOCK_UNCERTAINTY_CONSTRAINT) $clocks
set_clock_uncertainty 2.5 -rise_from $clocks -fall_to $clocks
set_clock_uncertainty 2.0 -fall_from $clocks -rise_to $clocks
set_clock_transition $::env(CLOCK_TRANSITION_CONSTRAINT) $clocks

set_timing_derate -early [expr 1-[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]
set_timing_derate -late [expr 1+[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]

if { [info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] && $::env(OPENLANE_SDC_IDEAL_CLOCKS) } {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}
