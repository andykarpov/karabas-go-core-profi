# Command line build of the Profi core for the three boards: the steps and options of the ISE 14.7
# project navigator (the .xise projects of the boards, removed when this Makefile replaced them).
#
#   make                 all three boards (profi.kg1, profi.kg2, profi.kg3)
#   make go|mini|minig   one board: synthesis, implementation, bitstream, .kg file
#   make minig-xst       one step: <board>-xst (.ngc), <board>-impl (.bin), <board>-core (.kg)
#   make minig-report    LUTs, slices, block RAMs and the timing result of the last build (and of -ds80)
#   make minig-ds80      the timing of the last build with clk_bus at 24 MHz (the DS80 video mode, see below)
#   make clean           the intermediate files (not the .bin / .kg files, they are in git)
#
# Inputs per board: karabas_<board>.prj (the source list, the shared modules as
# "../modules/rtl/..."), .xst, .ucf, .ut.
# A step runs again when one of its inputs is newer than its output.
# The boards share xst/ and _ngo/, so they are built one after the other.

ISE_SETTINGS ?= /opt/Xilinx/14.7/ISE_DS/settings64.sh
PART = xc6slx25-ftg256-2
BOARDS = go mini minig

SHELL = /bin/bash
.SHELLFLAGS = -e -o pipefail -c
.NOTPARALLEL:
# settings64.sh takes the arguments of the shell that sources it: none here
XIL = source $(ISE_SETTINGS) > /dev/null;

KG_go = profi.kg1
KG_mini = profi.kg2
KG_minig = profi.kg3
JSON_go = core.json
JSON_mini = core_mini.json
JSON_minig = core_minig.json

# map / par options (as the .xise projects had them)
MAP_T_go ?= 1
MAP_T_mini ?= 2
MAP_T_minig ?= 2

MAP_go = -logic_opt off -ol high -t $(MAP_T_go) -xt 0 -register_duplication off -r 4 -global_opt off -mt 2 -ir off -pr b -lc auto -power off
PAR_go = -ol high -mt off
MAP_mini = -logic_opt off -ol high -xe n -t $(MAP_T_mini) -xt 0 -register_duplication off -r 4 -global_opt off -mt 2 -detail -ir off -pr b -lc off -power off
PAR_mini = -ol high -xe n -mt 4
MAP_minig = $(subst -t $(MAP_T_mini) ,-t $(MAP_T_minig) ,$(MAP_mini))
PAR_minig = $(PAR_mini)

# included by the sources, not in the prj
INCLUDES = $(wildcard ../modules/rtl/mcu/*.vh rtl/vg93/*.vh) rtl/osd/icons.bit rtl/sound/saa1099_compressor_lut.hex

.PHONY: all clean $(BOARDS) $(BOARDS:=-xst) $(BOARDS:=-impl) $(BOARDS:=-core) $(BOARDS:=-report) $(BOARDS:=-ds80)

# clk_bus is a BUFGMUX of 28 MHz (pll_clk<0>) and 24 MHz (pll_clk<1>, the DS80 mode); both PERIODs cover the same
# flip-flops and trce analyses them at 28 MHz only. <board>-ds80 runs trce again with the PERIOD of pll_clk<0> set
# to 24 MHz: the paths in clk_bus and to the other clocks (clk_8, HDMI DCM) with the phases of 24 MHz. Not active in
# the DS80 mode, so ignored there: clk_bus <-> clk_gs (the host does not access the General Sound with DS80, gs.v;
# its audio crosses through the filter in profi.vhd) and clk_bus -> clk_sdr (the ROM loader, which resets DS80).
DS80_TIG = PATH TS_DS80_BUS_GS = FROM TIMEGRP "U1_U1_pll_clk_0_" TO TIMEGRP "U1_U1_U2_clkout_2_";\n\
PATH "TS_DS80_BUS_GS" TIG;\n\
PATH TS_DS80_GS_BUS = FROM TIMEGRP "U1_U1_U2_clkout_2_" TO TIMEGRP "U1_U1_pll_clk_0_";\n\
PATH "TS_DS80_GS_BUS" TIG;\n\
PATH TS_DS80_BUS_SDR = FROM TIMEGRP "U1_U1_pll_clk_0_" TO TIMEGRP "U1_U1_U2_clkout_3_";\n\
PATH "TS_DS80_BUS_SDR" TIG;\n

all: $(BOARDS)

define board
SRC_$(1) := $$(shell sed -n 's/^[a-z]* work "\(.*\)"/\1/p' karabas_$(1).prj)

karabas_$(1).ngc: karabas_$(1).prj karabas_$(1).xst $$(SRC_$(1)) $(INCLUDES)
	mkdir -p xst/projnav.tmp
	$(XIL) xst -intstyle ise -ifn karabas_$(1).xst -ofn karabas_$(1).syr

karabas_$(1).bin: karabas_$(1).ngc karabas_$(1).ucf karabas_$(1).ut
	$(XIL) ngdbuild -intstyle ise -dd _ngo -nt timestamp -uc karabas_$(1).ucf -p $(PART) karabas_$(1).ngc karabas_$(1).ngd
	$(XIL) map -intstyle ise -p $(PART) -w $(MAP_$(1)) -o karabas_$(1)_map.ncd karabas_$(1).ngd karabas_$(1).pcf
	$(XIL) par -w -intstyle ise $(PAR_$(1)) karabas_$(1)_map.ncd karabas_$(1).ncd karabas_$(1).pcf
	$(XIL) trce -intstyle ise -v 3 -s 2 -n 3 -fastpaths -xml karabas_$(1).twx karabas_$(1).ncd -o karabas_$(1).twr karabas_$(1).pcf -ucf karabas_$(1).ucf
	$(XIL) bitgen -intstyle ise -f karabas_$(1).ut karabas_$(1).ncd

$(KG_$(1)): karabas_$(1).bin $(JSON_$(1)) $$(wildcard roms/*)
	python3 make_core.py $(JSON_$(1)) $$@

$(1): $(KG_$(1))
$(1)-xst: karabas_$(1).ngc
$(1)-impl: karabas_$(1).bin
$(1)-core: $(KG_$(1))
$(1)-report:
	@grep -E "Number of (Slice LUTs|occupied Slices|RAMB16BWERs|RAMB8BWERs):" karabas_$(1)_map.mrp
	@grep -E "constraints? (was|were) met|constraints? not met|Timing Score" karabas_$(1).par | sort -u
	@if [ -f karabas_$(1)_ds80.twr ]; then echo "DS80 (clk_bus 24 MHz):"; \
		grep -E "constraints? (was|were) met|constraints? not met|Timing errors" karabas_$(1)_ds80.twr | sort -u; fi
$(1)-ds80: karabas_$(1)_ds80.twr
karabas_$(1)_ds80.twr: karabas_$(1).bin
	sed -E '/^TS_U1_U1_pll_clk_0_ = PERIOD/{s#/ 0\.5625#/ 0.482142857#;n;s#/ 0\.5625#/ 0.482142857#}' \
		karabas_$(1).pcf > karabas_$(1)_ds80.pcf
	grep -A1 "^TS_U1_U1_pll_clk_0_ = PERIOD" karabas_$(1)_ds80.pcf | grep -q 0.482142857
	printf '$(DS80_TIG)' >> karabas_$(1)_ds80.pcf
	$(XIL) trce -intstyle ise -v 3 -s 2 -n 3 -fastpaths karabas_$(1).ncd -o karabas_$(1)_ds80.twr karabas_$(1)_ds80.pcf \
		| tee karabas_$(1)_ds80.log | grep -E "ERROR|WARNING" || true
	@! grep -q "No timing constraints found" karabas_$(1)_ds80.twr || { echo "trce did not read karabas_$(1)_ds80.pcf"; \
		rm -f karabas_$(1)_ds80.twr; exit 1; }
endef

$(foreach b,$(BOARDS),$(eval $(call board,$(b))))

clean:
	rm -rf xst _ngo _xmsgs xlnx_auto_0_xdb iseconfig
	rm -f $(foreach b,$(BOARDS),$(addprefix karabas_$(b),.ngc .ngd .ngr .syr .lso .bld .pcf .ncd _map.ncd _map.ngm \
		_map.map _map.mrp _map.xrpt .par .pad _pad.csv _pad.txt .twr .twx .unroutes .xpi .ptwx .bgn .bit .drc \
		_bitgen.xwbt _summary.xml _usage.xml _xst.xrpt _ngdbuild.xrpt _par.xrpt _guide.ncd _ds80.pcf _ds80.twr _ds80.log))
