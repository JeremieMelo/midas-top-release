##################
#   Parameters   #
##################
PLATFORM ?= zynq
#PLATFORM ?= catapult
EMUL ?= verilator
PROJECT ?= midas.top
# PROJECT ?= simplenic
DESIGN ?= MidasTop
CONFIG ?= DefaultExampleConfig
# CONFIG ?= SmallBOOMConfig
# CONFIG ?= SimpleNicConfig
STROBER ?=
DRIVER ?=
SAMPLE ?=
ARGS ?= +dramsim

base_dir = $(abspath .)
simif_dir = $(base_dir)/midas/src/main/cc
driver_dir = $(base_dir)/src/main/cc
generated_dir = $(base_dir)/generated-src/$(PLATFORM)/$(CONFIG)
output_dir = $(base_dir)/output/$(PLATFORM)/$(CONFIG)

driver_h = $(wildcard $(driver_dir)/*.h)
emul_cc = $(addprefix $(driver_dir)/, $(addsuffix .cc, midas_top_emul midas_fesvr midas_tsi))
midas_h = $(wildcard $(simif_dir)/*.h) $(wildcard $(simif_dir)/utils/*.h) \
	$(wildcard $(simif_dir)/endpoints/*.h)
midas_cc = $(wildcard $(simif_dir)/*.cc) $(wildcard $(simif_dir)/utils/*.cc) \
	$(wildcard $(simif_dir)/endpoints/*.cc)

SBT ?= sbt
SBT_FLAGS ?=

src_path = src/main/scala
submodules = . rocket-chip rocket-chip/hardfloat rocket-chip/context-dependent-environments \
	testchipip boom chisel firrtl midas
chisel_srcs = $(foreach submodule,$(submodules),$(shell find $(base_dir)/$(submodule)/$(src_path) -name "*.scala"))

shim := $(shell echo $(PLATFORM) | cut -c 1 | tr [:lower:] [:upper:])$(shell echo $(PLATFORM) | cut -c 2-)Shim

verilog = $(generated_dir)/$(shim).v
$(verilog): $(chisel_srcs)
	$(SBT) $(SBT_FLAGS) \
	"run $(if $(STROBER),strober,midas) $(patsubst $(base_dir)/%,%,$(dir $@)) $(PROJECT) $(DESIGN) $(PROJECT) $(CONFIG) $(PLATFORM)"
verilog: $(verilog)

header = $(generated_dir)/$(DESIGN)-const.h
$(header): $(verilog)

compile: $(generated_dir)/ZynqShim.v

ifneq ($(filter run% %.run %.out %.vpd %.vcd,$(MAKECMDGOALS)),)
-include $(generated_dir)/$(PROJECT).d
endif

timeout_cycles = 100000000
disasm := 2>
which_disasm := $(shell which spike-dasm 2> /dev/null)
ifneq ($(which_disasm),)
        disasm := 3>&1 1>&2 2>&3 | $(which_disasm) $(DISASM_EXTENSION) >
endif

######################
# Veriltor Emulation #
######################
verilator = $(generated_dir)/V$(DESIGN)
verilator_debug = $(generated_dir)/V$(DESIGN)-debug

$(verilator) $(verilator_debug): export CXXFLAGS := $(CXXFLAGS) -I$(RISCV)/include
$(verilator) $(verilator_debug): export LDFLAGS := $(LDFLAGS) -L$(RISCV)/lib -lfesvr -Wl,-rpath,$(RISCV)/lib

$(verilator): $(header) $(emul_cc) $(driver_h) $(midas_cc) $(midas_h)
	$(MAKE) -C $(simif_dir) verilator PLATFORM=$(PLATFORM) DESIGN=$(DESIGN) \
	GEN_DIR=$(generated_dir) DRIVER="$(emul_cc)"

$(verilator_debug): $(header) $(emul_cc) $(driver_h) $(midas_cc) $(midas_h)
	$(MAKE) -C $(simif_dir) verilator-debug PLATFORM=$(PLATFORM) DESIGN=$(DESIGN) \
	GEN_DIR=$(generated_dir) DRIVER="$(emul_cc)"

verilator: $(verilator)
verilator-debug: $(verilator_debug)

######################
#   VCS Emulation    #
######################
vcs = $(generated_dir)/$(DESIGN)
vcs_debug = $(generated_dir)/$(DESIGN)-debug

$(vcs) $(vcs_debug): export CXXFLAGS := $(CXXFLAGS) -I$(VCS_HOME)/include -I$(RISCV)/include
$(vcs) $(vcs_debug): export LDFLAGS := $(LDFLAGS) -L$(RISCV)/lib -lfesvr -Wl,-rpath,$(RISCV)/lib

$(vcs): $(header) $(emul_cc) $(driver_h) $(midas_cc) $(midas_h)
	$(MAKE) -C $(simif_dir) vcs PLATFORM=$(PLATFORM) DESIGN=$(DESIGN) \
	GEN_DIR=$(generated_dir) DRIVER="$(emul_cc)"

$(vcs_debug): $(header) $(emul_cc) $(driver_h) $(midas_cc) $(midas_h)
	$(MAKE) -C $(simif_dir) vcs-debug PLATFORM=$(PLATFORM) DESIGN=$(DESIGN) \
	GEN_DIR=$(generated_dir) DRIVER="$(emul_cc)"

vcs: $(vcs)
vcs-debug: $(vcs_debug)

######################
#  Emulation Rules   #
######################
$(output_dir)/%.run: $(output_dir)/% $(EMUL)
	cd $(dir $($(EMUL))) && \
	./$(notdir $($(EMUL))) $< +sample=$<.sample +max-cycles=$(timeout_cycles) $(ARGS) \
	2> /dev/null 2> $@ && [ $$PIPESTATUS -eq 0 ]

$(output_dir)/%.out: $(output_dir)/% $(EMUL)
	cd $(dir $($(EMUL))) && \
	./$(notdir $($(EMUL))) $< +sample=$<.sample +max-cycles=$(timeout_cycles) $(ARGS) \
	$(disasm) $@ && [ $$PIPESTATUS -eq 0 ]

$(output_dir)/%.vpd: $(output_dir)/% $(EMUL)-debug
	cd $(dir $($(EMUL)_debug)) && \
	./$(notdir $($(EMUL)_debug)) $< +sample=$<.sample +waveform=$@ +max-cycles=$(timeout_cycles) $(ARGS) \
	$(disasm) $(patsubst %.vpd,%.out,$@) && [ $$PIPESTATUS -eq 0 ]

######################
#   Smaple Replays   #
######################

$(generated_dir)/$(DESIGN).v: $(chisel_srcs)
	$(SBT) $(SBT_FLAGS) "run replay $(patsubst $(base_dir)/%,%,$(dir $@)) $(PROJECT) $(DESIGN) $(PROJECT) $(CONFIG)"

compile-replay: $(generated_dir)/$(DESIGN).v

vcs_replay = $(generated_dir)/$(DESIGN)-replay

$(vcs_replay): $(generated_dir)/$(DESIGN).v $(midas_cc) $(midas_h)
	$(MAKE) -C $(simif_dir) vcs-replay PLATFORM=$(PLATFORM) DESIGN=$(DESIGN) GEN_DIR=$(dir $<)

vcs-replay: $(vcs_replay)
ifdef SAMPLE
	$(vcs_replay) +sample=$(abspath $(SAMPLE)) +verbose \
	+waveform=$(output_dir)/$(DESIGN)-replay.vpd \
	$(disasm) $(output_dir)/$(DESIGN)-replay.out && [ $$PIPESTATUS -eq 0 ]
endif

$(output_dir)/%.sample: $(output_dir)/%.out

$(output_dir)/%-replay.vpd: $(output_dir)/%.sample $(vcs_replay)
	$(vcs_replay) +sample=$(output_dir)/$*.sample +verbose +waveform=$@ $(disasm) $(patsubst %.vpd,%.out,$@) && [ $$PIPESTATUS -eq 0 ]

######################
#   FPGA Simulation  #
######################
$(output_dir)/$(DESIGN).chain: $(verilog)
	mkdir -p $(output_dir)
	$(if $(wildcard $(generated_dir)/$(DESIGN).chain),cp $(generated_dir)/$(DESIGN).chain $@,)

$(PLATFORM) = $(output_dir)/$(DESIGN)-$(PLATFORM)

$(PLATFORM): $($(PLATFORM)) $(output_dir)/$(DESIGN).chain

fesvr_dir = $(base_dir)/riscv-fesvr
ifeq ($(PLATFORM),zynq)
# Compile Frontend Server
host = arm-xilinx-linux-gnueabi

$(output_dir)/build/libfesvr.so: $(wildcard $(fesvr_dir)/fesvr/*.cc) $(wildcard $(fesvr_dir)/fesvr/*.h)
	mkdir -p $(dir $@)
	cd $(dir $@) && $(fesvr_dir)/configure --host=$(host)
	$(MAKE) -C $(dir $@)

$(output_dir)/libfesvr.so: $(output_dir)/build/libfesvr.so
	mkdir -p $(dir $@)
	cp $< $@

# Compile Driver
zynq_cc = $(addprefix $(driver_dir)/, $(addsuffix .cc, midas_top_zynq midas_fesvr midas_tsi))

$(zynq): $(header) $(zynq_cc) $(driver_h) $(midas_cc) $(midas_h) $(output_dir)/libfesvr.so
	mkdir -p $(dir @)/build
	cp $(header) $(dir $@)/build/
	$(MAKE) -C $(simif_dir) zynq PLATFORM=zynq DESIGN=$(DESIGN) \
	GEN_DIR=$(dir $@)/build OUT_DIR=$(dir $@) DRIVER="$(zynq_cc)" \
	CXX="$(host)-g++" \
	CXXFLAGS="$(CXXFLAGS) -I$(RISCV)/include" \
	LDFLAGS="$(LDFLAGS) -L$(output_dir) -lfesvr -Wl,-rpath,/usr/local/lib"
endif

ifeq ($(PLATFORM),catapult)
# Frontend Server: Should compile in Cygwin
fesvr_files = elfloader htif memif syscall device rfb context term
fesvr_h = $(addprefix $(fesvr_dir)/fesvr/, $(addsuffix .h, $(fesvr_files) configstring encoding elf))
fesvr_o = $(addprefix $(output_dir)/build/, $(addsuffix .o, $(fesvr_files)))
$(fesvr_o): $(output_dir)/build/%.o: $(fesvr_dir)/fesvr/%.cc $(fesvr_h)
	mkdir -p $(output_dir)/build
	g++ -DPREFIX="" -I$(fesvr_dir)/fesvr -std=c++11 -c -o $@ $<

midas_fesvr_files = channel midas_fesvr mmap_fesvr
midas_fesvr_h = $(addprefix $(driver_dir)/,       $(addsuffix .h, $(midas_fesvr_files)))
midas_fesvr_o = $(addprefix $(output_dir)/build/, $(addsuffix .o, $(midas_fesvr_files)))
$(midas_fesvr_o): $(output_dir)/build/%.o: $(driver_dir)/%.cc $(midas_fesvr_h)
	mkdir -p $(output_dir)/build
	g++ -I$(fesvr_dir) -std=c++11 -c -o $@ $<

fesvr = $(output_dir)/midas-fesvr
fesvr: $(fesvr)
$(fesvr): $(fesvr_o) $(midas_fesvr_o)
	g++ -o $@ $^

# Compile Driver
catapult_cc = $(addprefix $(driver_dir)/, $(addsuffix .cc, midas_top_catapult channel))

$(catapult): $(header) $(catapult_cc) $(driver_h) $(midas_cc) $(midas_h) $(fesvr)
	mkdir -p $(dir @)/build
	cp $(header) $(dir $@)/build/
	$(MAKE) -C $(simif_dir) catapult PLATFORM=catapult DESIGN=$(DESIGN) \
	GEN_DIR=$(dir $@)/build OUT_DIR=$(dir $@) DRIVER="$(catapult_cc) $(DRIVER)" \
	CXX=cl AR=lib CXXFLAGS="$(CXXFLAGS)" LDFLAGS="$(LDFLAGS)"
endif

ifeq ($(PLATFORM),zynq)
# Generate Bitstream
board     ?= zc706
board_dir := $(base_dir)/midas-$(PLATFORM)/$(board)
bitstream := fpga-images-$(board)/boot.bin

$(board_dir)/src/verilog/$(CONFIG)/ZynqShim.v: $(verilog)
	$(MAKE) -C $(board_dir) clean DESIGN=$(CONFIG)
	mkdir -p $(dir $@)
	cp $< $@

$(output_dir)/boot.bin: $(board_dir)/src/verilog/$(CONFIG)/ZynqShim.v
	mkdir -p $(dir $@)
	$(MAKE) -C $(board_dir) $(bitstream) DESIGN=$(CONFIG)
	cp $(board_dir)/$(bitstream) $@

$(output_dir)/midas_wrapper.bit: $(board_dir)/src/verilog/ZynqShim.v
	mkdir -p $(dir $@)
	cp -L $(board_dir)/fpga-images-$(board)/boot_image/midas_wrapper.bit $@

fpga: $(output_dir)/boot.bin $(output_dir)/midas_wrapper.bit
endif

mostlyclean:
	rm -rf $(verilator) $(verilator_debug) $(vcs) $(vcs_debug) $($(PLATFORM)) $(output_dir)

clean:
	rm -rf $(generated_dir) $(output_dir)

.PHONY: verilog compile verilator verilator-debug vcs vcs-debug $(PLATFORM) fpga mostlyclean clean

.PRECIOUS: $(output_dir)/%.vpd $(output_dir)/%.out $(output_dir)/%.run
