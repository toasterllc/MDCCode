TOOLCHAIN := "../../../Tools/gcc-msp430"

OBJS := 					\
	InterruptVector.o 		\
	main.o

ORDERED_OBJS :=				\
    -T"msp430fr2433.ld"     \
    -T"Linker.ld"			\
    $(OBJS)					\
    -Wl,--start-group 		\
    -lgcc 					\
    -lc 					\
    -Wl,--end-group

INCLUDES :=					\
	-I$(TOOLCHAIN)/include	\
	-I"."					\
	-I"../../.."

EXE_OUTPUT := MSPApp.elf

GCC := $(TOOLCHAIN)/platform/bin/msp430-elf-gcc

$(EXE_OUTPUT): $(OBJS)
	$(GCC) -mhwmult=f5series -fno-exceptions -Os -ffunction-sections -fdata-sections					\
		-g -gdwarf-4 -Wall -flto -mmcu=msp430fr2433 -Wl,-Map,"MSPApp.map" -nostartfiles -static			\
		-Wl,--gc-sections -mmcu=msp430fr2433 -L$(TOOLCHAIN)/include										\
		-Wl,-flto -o$(EXE_OUTPUT) $(ORDERED_OBJS)

%.o: %.cpp
	# Unpack the toolchain as needed
	$(TOOLCHAIN)/setup.sh
	
	$(GCC) $(INCLUDES) -c -mmcu=msp430fr2433 -mhwmult=f5series -fno-exceptions							\
		-Os -ffunction-sections -fdata-sections -g -gdwarf-4 -Wall -flto -MMD -MP						\
		-MF"$(basename $(<F)).d_raw" -MT"$(@)" -std=c++17 -fno-rtti -fno-threadsafe-statics				\
		-o"$@" "$(shell echo $<)"

clean:
	rm -rf $(EXE_OUTPUT) *.o *.d *.d_raw *.map
