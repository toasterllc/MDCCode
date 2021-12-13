################################################################################
# Automatically-generated file. Do not edit!
################################################################################

# Each subdirectory must supply rules for building sources it contributes
main.o: ../main.cpp $(GEN_OPTS) | $(GEN_FILES) $(GEN_MISC_FILES)
	@echo 'Building file: "$<"'
	@echo 'Invoking: GNU Compiler'
	"/home/dave/ti/ccs1040/ccs/tools/compiler/msp430-gcc-9.3.1.11_linux64/bin/msp430-elf-gcc-9.3.1" -c -mmcu=msp430fr2433 -mhwmult=auto -fno-exceptions -I"/home/dave/ti/ccs1040/ccs/ccs_base/msp430/include_gcc" -I"/home/dave/repos/MDC/Code/MSP430/ThreadTest-LaunchpadFR" -I"/home/dave/ti/ccs1040/ccs/tools/compiler/msp430-gcc-9.3.1.11_linux64/msp430-elf/include" -I"/home/dave/repos/MDC/Code/Shared" -I"/home/dave/repos/MDC/Code/Lib" -Os -g -gdwarf-3 -gstrict-dwarf -Wall -MMD -MP -MF"$(basename $(<F)).d_raw" -MT"$(basename\ $(<F)).o" -std=c++17 -fno-rtti -fno-threadsafe-statics $(GEN_OPTS__FLAG) -o"$@" "$(shell echo $<)"
	@echo 'Finished building: "$<"'
	@echo ' '


