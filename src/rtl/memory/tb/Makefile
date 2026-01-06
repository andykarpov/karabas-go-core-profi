all: testbench_top

testbench_top: IVFLAGS+=-I../
testbench_top: sram_tb.v ../sram.v

testbench_%:
	iverilog -g2005-sv ${IVFLAGS} -o $@.vvp $^
	vvp $@.vvp
	gtkwave tb.gtkw
	@rm $@.vvp

clean:
	rm -rf *.vcd *.vvp

-include Makefile.local
