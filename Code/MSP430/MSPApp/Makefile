ORDERED_OBJS :=				\
    -T"msp430fr2433.ld"     \
    -T"Linker.ld"			\
    "InterruptVector.o" 	\
    "main.o" 				\
    -Wl,--start-group 		\
    -lgcc 					\
    -lc 					\
    -Wl,--end-group

EXE_OUTPUT := MSPApp.elf

CPP_SRCS := 			\
	InterruptVector.cpp \
	main.cpp

LD_SRCS := 				\
	Linker.ld 			\
	msp430fr2433.ld

OBJS := 				\
	InterruptVector.o 	\
	main.o

%.o: %.cpp | $(GEN_FILES) $(GEN_MISC_FILES)
	"msp430-elf-gcc-9.3.1" -c -mmcu=msp430fr2433 -mhwmult=f5series -fno-exceptions						\
		-I"." -I"../../../" -I"/Users/dave/Desktop/msp430-gcc-support-files/include"					\
		-Os -ffunction-sections -fdata-sections -g -gdwarf-4 -Wall -flto -MMD -MP						\
		-MF"$(basename $(<F)).d_raw" -MT"$(@)" -std=c++17 -fno-rtti -fno-threadsafe-statics				\
		-o"$@" "$(shell echo $<)"

# Tool invocations
$(EXE_OUTPUT): $(OBJS) $(LD_SRCS) $(GEN_CMDS)
	"msp430-elf-gcc-9.3.1" -mhwmult=f5series -fno-exceptions -Os -ffunction-sections -fdata-sections	\
		-g -gdwarf-4 -Wall -flto -mmcu=msp430fr2433 -Wl,-Map,"MSPApp.map" -nostartfiles -static			\
		-Wl,--gc-sections -mmcu=msp430fr2433 -L"/Users/dave/Desktop/msp430-gcc-support-files/include"	\
		-Wl,-flto -o$(EXE_OUTPUT) $(ORDERED_OBJS)

# Other Targets
clean:
	rm -rf $(EXE_OUTPUT) *.o *.d *.d_raw *.map

.PHONY: all clean dependents
.SECONDARY:
