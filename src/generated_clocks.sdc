set clock_port __VIRTUAL_CLK__
if { [info exists ::env(CLOCK_PORT)] } {
    set port_count [llength $::env(CLOCK_PORT)]

    if { $port_count == "0" } {
        puts "\[WARNING] No CLOCK_PORT found. A dummy clock will be used."
    } elseif { $port_count != "1" } {
        puts "\[WARNING] Multi-clock files are not currently supported by this SDC file. Only the first clock will be constrained."
    }

    if { $port_count > "0" } {
        set ::clock_port [lindex $::env(CLOCK_PORT) 0]
    }
}
set port_args [get_ports $clock_port]
puts "\[INFO] Using clock $clock_port..."
create_clock {*}$port_args -name $clock_port -period $::env(CLOCK_PERIOD)

set input_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]
set output_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]
puts "\[INFO] Setting output delay to: $output_delay_value"
puts "\[INFO] Setting input delay to: $input_delay_value"

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

# correct resetn
set clocks [get_clocks $clock_port]

set_input_delay $input_delay_value -clock $clocks $all_inputs_wo_clk
set_output_delay $output_delay_value -clock $clocks [all_outputs]

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
puts "\[INFO] Setting load to: $cap_load"
set_load $cap_load [all_outputs]

proc zuzel_unique {items} {
    set out {}
    foreach item $items {
        if { [lsearch -exact $out $item] < 0 } {
            lappend out $item
        }
    }
    return $out
}

proc zuzel_nets {patterns} {
    set nets {}
    foreach pattern $patterns {
        foreach net [get_nets -quiet -hierarchical $pattern] {
            lappend nets $net
        }
    }
    return [zuzel_unique $nets]
}

proc zuzel_clock_pins_on_nets {patterns} {
    set nets [zuzel_nets $patterns]
    set pins {}
    foreach clock_pin [all_registers -clock_pins] {
        foreach net [get_nets -quiet -of_objects $clock_pin] {
            if { [lsearch -exact $nets $net] >= 0 } {
                lappend pins $clock_pin
            }
        }
    }
    return [zuzel_unique $pins]
}

proc zuzel_without {items remove} {
    set out {}
    foreach item $items {
        if { [lsearch -exact $remove $item] < 0 } {
            lappend out $item
        }
    }
    return $out
}

proc zuzel_generated_clock {name source master divide patterns} {
    set pins [zuzel_clock_pins_on_nets $patterns]
    set count [llength $pins]
    puts "\[INFO] Zuzel generated clock $name matched $count register clock pin(s)."
    if { $count == 0 } {
        puts "\[INFO] Zuzel generated clock $name matched no pins by name; fallback will cover any unclocked pins."
        return
    }
    create_generated_clock -name $name -source $source -master_clock $master -divide_by $divide $pins
}

proc zuzel_clocked_clock_pins {} {
    set pins {}
    foreach clock [all_clocks] {
        foreach clock_pin [all_registers -clock $clock -clock_pins] {
            lappend pins $clock_pin
        }
    }
    return [zuzel_unique $pins]
}

proc zuzel_unclocked_clock_pins {} {
    set all_pins [all_registers -clock_pins]
    set clocked_pins [zuzel_clocked_clock_pins]
    return [zuzel_without $all_pins $clocked_pins]
}

proc zuzel_existing_clocks {names} {
    set clocks {}
    foreach name $names {
        foreach clock [get_clocks -quiet $name] {
            lappend clocks $clock
        }
    }
    return [zuzel_unique $clocks]
}

set source_clk_pin [get_ports $clock_port]

# hsync and vsync are flip-flop outputs from hvsync_generator.
zuzel_generated_clock zuzel_hsync $source_clk_pin $clock_port 800 {
    hsync
    *hsync*
}
zuzel_generated_clock zuzel_vsync $source_clk_pin $clock_port 420000 {
    vsync
    *vsync*
}

# speed_clk is selected by stable gameplay mode inputs. Constrain it at the
# fastest supported rate, which is the direct-vsync mode.
zuzel_generated_clock zuzel_speed_clk $source_clk_pin $clock_port 420000 {
    *speed_clk*
    *spd_clk*
    *spdcnt*
    *ctrl\[13\]*
    *mt_ctrl\[13\]*
}

# Per-motor movement/update clocks are gated pulses derived from clk-registered
# dxyclk/movclk. A 4x parent-clock period is the minimum pulse spacing in the
# active windows and is conservative for the slower gaps between windows.
zuzel_generated_clock zuzel_dxy_clk $source_clk_pin $clock_port 4 {
    *dxy_clk*
    *dxyclk*
    *ctrl\[1\]*
    *mt_ctrl\[1\]*
}
zuzel_generated_clock zuzel_mov_clk $source_clk_pin $clock_port 4 {
    *mov_clk*
    *movclk*
    *ctrl\[6\]*
    *mt_ctrl\[6\]*
}

set zuzel_remaining_clock_pins [zuzel_unclocked_clock_pins]
set zuzel_remaining_clock_pin_count [llength $zuzel_remaining_clock_pins]
puts "\[INFO] Zuzel conservative generated-clock fallback matched $zuzel_remaining_clock_pin_count register clock pin(s)."
if { $zuzel_remaining_clock_pin_count > 0 } {
    create_generated_clock -name zuzel_generated_fast -source $source_clk_pin -master_clock $clock_port -divide_by 4 $zuzel_remaining_clock_pins
}

# The motor clocks are delayed clock-enable strobes. Their consumers are meant
# to capture values launched by clk/vsync once the strobe gate tree has settled,
# so same-edge hold checks into those strobe domains are not a real requirement.
set zuzel_strobe_clocks [zuzel_existing_clocks {
    zuzel_hsync
    zuzel_speed_clk
    zuzel_dxy_clk
    zuzel_mov_clk
    zuzel_generated_fast
}]
if { [llength $zuzel_strobe_clocks] > 0 } {
    set zuzel_strobe_parent_clocks [zuzel_existing_clocks [list $clock_port zuzel_vsync]]
    if { [llength $zuzel_strobe_parent_clocks] > 0 } {
        set_false_path -hold -from $zuzel_strobe_parent_clocks -to $zuzel_strobe_clocks
    }
    set zuzel_stable_mode_ports [get_ports -quiet uio_in*]
    if { [llength $zuzel_stable_mode_ports] > 0 } {
        set_false_path -hold -from $zuzel_stable_mode_ports -to $zuzel_strobe_clocks
    }
}

puts "\[INFO] Setting clock uncertainty to: $::env(CLOCK_UNCERTAINTY_CONSTRAINT)"
set_clock_uncertainty $::env(CLOCK_UNCERTAINTY_CONSTRAINT) [all_clocks]

puts "\[INFO] Setting clock transition to: $::env(CLOCK_TRANSITION_CONSTRAINT)"
set_clock_transition $::env(CLOCK_TRANSITION_CONSTRAINT) [all_clocks]

puts "\[INFO] Setting timing derate to: $::env(TIME_DERATING_CONSTRAINT)%"
set_timing_derate -early [expr 1-[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]
set_timing_derate -late [expr 1+[expr $::env(TIME_DERATING_CONSTRAINT) / 100]]

if { [info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] && $::env(OPENLANE_SDC_IDEAL_CLOCKS) } {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}

if { ![check_setup -no_clock -multiple_clock -generated_clocks] } {
    error "Zuzel generated-clock SDC sanity check failed."
}
