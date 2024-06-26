################################################################################
# Automatically-generated file. Do not edit!
################################################################################

# Each subdirectory must supply rules for building sources it contributes
%.o: ../%.cpp $(GEN_OPTS) | $(GEN_FILES) $(GEN_MISC_FILES)
	@echo 'Building file: "$<"'
	@echo 'Invoking: GNU Compiler'
	"msp430-elf-gcc-9.3.1" -c -mmcu=msp430fr2433 -mhwmult=f5series -fno-exceptions -I"../" -I"../../../../" -I"/Users/dave/Desktop/msp430-gcc-support-files/include" -Os -ffunction-sections -fdata-sections -g -gdwarf-4 -Wall -flto -MMD -MP -MF"$(basename $(<F)).d_raw" -MT"$(@)" -std=c++17 -fno-rtti -fno-threadsafe-statics $(GEN_OPTS__FLAG) -o"$@" "$(shell echo $<)"
	@echo 'Finished building: "$<"'
	@echo ' '


