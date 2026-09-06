# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = project.v reset_synchronizer.v arm16_controller.v arm16_datapath.v \
                  instruction_decoder.v condition_checker.v register_file.v barrel_shifter.v alu.v \
                  hazard_detector.v forwarding_selector.v demo_rom.v qspi_master.v vga_renderer.v

# The RTL suite replaces the sixteen-word demo ROM with the 1,024-word test ROM that cocotb fills by
# hierarchy (ROMTEST=yes, the default for RTL; ROMTEST=no builds the shipped ROM; the gate-level
# netlist always carries the real ROM). test_software.py proves src/demo_rom.v matches programs/demo_rom.s.
ifneq ($(GATES),yes)
ROMTEST ?= yes
endif
ifeq ($(ROMTEST),yes)
PROJECT_SOURCES := $(filter-out demo_rom.v,$(PROJECT_SOURCES))
export ROMTEST
endif

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD				= sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
ifeq ($(ROMTEST),yes)
VERILOG_SOURCES += $(PWD)/test_rom.v
SIM_BUILD				= sim_build/romtest
endif

else

# Gate level simulation:
SIM_BUILD				= sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DUSE_POWER_PINS
COMPILE_ARGS    += -DSIM
COMPILE_ARGS    += -DUNIT_DELAY=\#1
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v

# this gets copied in by the GDS action workflow
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

export GATES

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS 		+= -I$(SRC_DIR)

# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL = tb

# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
