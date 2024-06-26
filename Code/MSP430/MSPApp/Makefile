ORDERED_OBJS :=				\
    -T"msp430fr2433.ld"     \
    -T"Linker.ld"			\
    "InterruptVector.o" 	\
    "main.o" 				\
    -Wl,--start-group 		\
    -lgcc 					\
    -lc 					\
    -Wl,--end-group

RM := rm -rf
BIN_OUTPUTS := MSPApp.hex
LIBS := -lgcc -lc
EXE_OUTPUTS := MSPApp.out

CPP_SRCS := 			\
	InterruptVector.cpp \
	main.cpp

LD_SRCS := 				\
	Linker.ld 			\
	msp430fr2433.ld

OBJS := 				\
	InterruptVector.o 	\
	main.o


%.o: %.cpp $(GEN_OPTS) | $(GEN_FILES) $(GEN_MISC_FILES)
	@echo 'Building file: "$<"'
	@echo 'Invoking: GNU Compiler'
	"msp430-elf-gcc-9.3.1" -c -mmcu=msp430fr2433 -mhwmult=f5series -fno-exceptions -I"." -I"../../../" -I"/Users/dave/Desktop/msp430-gcc-support-files/include" -Os -ffunction-sections -fdata-sections -g -gdwarf-4 -Wall -flto -MMD -MP -MF"$(basename $(<F)).d_raw" -MT"$(@)" -std=c++17 -fno-rtti -fno-threadsafe-statics $(GEN_OPTS__FLAG) -o"$@" "$(shell echo $<)"
	@echo 'Finished building: "$<"'
	@echo ' '



# All Target
all:
	@$(MAKE) --no-print-directory pre-build
	@$(MAKE) --no-print-directory main-build

# Main-build Target
main-build: $(OBJS) $(LD_SRCS) $(GEN_CMDS)
	@$(MAKE) --no-print-directory "MSPApp.out"

# Tool invocations
MSPApp.out: $(OBJS) $(LD_SRCS) $(GEN_CMDS)
	@echo 'Building target: "$@"'
	@echo 'Invoking: GNU Linker'
	"msp430-elf-gcc-9.3.1" -mhwmult=f5series -fno-exceptions -Os -ffunction-sections -fdata-sections -g -gdwarf-4 -Wall -flto -mmcu=msp430fr2433 -Wl,-Map,"MSPApp.map" -nostartfiles -static -Wl,--gc-sections -mmcu=msp430fr2433 -L"/Users/dave/Desktop/msp430-gcc-support-files/include" -Wl,-flto -o"MSPApp.out" $(ORDERED_OBJS)
	@echo 'Finished building target: "$@"'
	@echo ' '

MSPApp.hex: $(EXE_OUTPUTS)
	@echo 'Building secondary target: "$@"'
	@echo 'Invoking: GNU Objcopy Utility'
	"msp430-elf-objcopy"  $(EXE_OUTPUTS) "MSPApp.hex"
	@echo 'Finished building secondary target: "$@"'
	@echo ' '

# Other Targets
clean:
	rm -rf $(BIN_OUTPUTS) $(EXE_OUTPUTS) *.o *.d *.d_raw *.map

pre-build:
	-make clean
	-@echo ' '

.PHONY: all clean dependents
.SECONDARY:
