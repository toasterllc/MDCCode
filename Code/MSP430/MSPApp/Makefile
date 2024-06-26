TOOLCHAIN := "../../../Tools/msp430-gcc"

OBJS := 					\
	InterruptVector.o 		\
	main.o					\

ORDERED_OBJS :=				\
    -T"msp430fr2433.ld"     \
    -T"Linker.ld"			\
    $(OBJS)					\
    -Wl,--start-group 		\
    -lgcc 					\
    -lc 					\
    -Wl,--end-group			\

INCLUDES :=								\
	-I$(TOOLCHAIN)/platform/include		\
	-I"."								\	# MSPApp
	-I"../../.."						\	# MDCCode

EXE_OUTPUT := MSPApp.elf

GCC := $(TOOLCHAIN)/platform/bin/msp430-elf-gcc

$(GCC):
	$(TOOLCHAIN)/unpack.sh

%.o: %.cpp | $(GEN_FILES) $(GEN_MISC_FILES)
	$(GCC) -c -mmcu=msp430fr2433 -mhwmult=f5series -fno-exceptions										\
		-I(INCLUDES)																					\
		-Os -ffunction-sections -fdata-sections -g -gdwarf-4 -Wall -flto -MMD -MP						\
		-MF"$(basename $(<F)).d_raw" -MT"$(@)" -std=c++17 -fno-rtti -fno-threadsafe-statics				\
		-o"$@" "$(shell echo $<)"

$(EXE_OUTPUT): $(OBJS) $(GEN_CMDS)
	$(GCC) -mhwmult=f5series -fno-exceptions -Os -ffunction-sections -fdata-sections					\
		-g -gdwarf-4 -Wall -flto -mmcu=msp430fr2433 -Wl,-Map,"MSPApp.map" -nostartfiles -static			\
		-Wl,--gc-sections -mmcu=msp430fr2433 -L"/Users/dave/Desktop/msp430-gcc-support-files/include"	\
		-Wl,-flto -o$(EXE_OUTPUT) $(ORDERED_OBJS)

clean:
	rm -rf $(EXE_OUTPUT) *.o *.d *.d_raw *.map

.PHONY: all clean
