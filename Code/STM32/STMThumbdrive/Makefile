OUTPUT := STMThumbdrive.elf
BUILDDIR := Build
TOOLCHAIN := "../../../Tools/gcc-stm32"
TOOLCHAINSETUP := $(shell $(TOOLCHAIN)/setup.sh) # Prepare toolchain
TOOLCHAINBIN := $(TOOLCHAIN)/platform/bin

SRCS := $(shell find Source -name '*.c' -o -name '*.s')

OBJS := $(addprefix $(BUILDDIR)/, $(addsuffix .o, $(basename $(SRCS))))

INCS :=																		\
	-iquote 'Source/Middlewares/Third_Party/FatFs/src'						\
	-iquote 'Source/FATFS/Target'											\
	-iquote 'Source/FATFS/App'												\
	-iquote 'Source/Core/Inc'												\
	-iquote 'Source/Drivers/STM32F7xx_HAL_Driver/Inc'						\
	-iquote 'Source/Drivers/CMSIS/Device/ST/STM32F7xx/Include'				\
	-iquote 'Source/Drivers/CMSIS/Include'									\
	-iquote 'Source/USB_DEVICE/App'											\
	-iquote 'Source/Middlewares/ST/STM32_USB_Device_Library/Core/Inc'		\
	-iquote 'Source/USB_DEVICE/Target'										\
	-iquote 'Source/Middlewares/ST/STM32_USB_Device_Library/Class/MSC/Inc'	\



# Link final product
$(BUILDDIR)/$(OUTPUT): $(OBJS)
	$(TOOLCHAINBIN)/arm-none-eabi-g++ -o $@ $(OBJS) -mcpu=cortex-m7 -T'Source/STM32F730I8KX_RAM.ld' -Wl,-Map=$(BUILDDIR)/$(OUTPUT:.elf=.map)	\
		-Wl,--gc-sections -static --specs=nano.specs -mfpu=fpv5-sp-d16 -mfloat-abi=hard -mthumb					\
		-Wl,--start-group -lc -lm -Wl,--end-group -Wl,--no-warn-rwx-segments

# C rules
$(BUILDDIR)/Source/%.o: Source/%.c
	mkdir -p $(dir $@)
	$(TOOLCHAINBIN)/arm-none-eabi-gcc "$<" -mcpu=cortex-m7 -std=c17 -g3 -DUSE_HAL_DRIVER -DSTM32F730xx -c -Os -ffunction-sections -fdata-sections		\
		-fno-exceptions -Wall																															\
		$(INCS) -fstack-usage -MMD -MP -MF"$(@:.o=.d)" -MT"$@"																							\
		--specs=nano.specs -mfpu=fpv5-sp-d16 -mfloat-abi=hard -mthumb -o "$@"

# Assembly rule
$(BUILDDIR)/Source/%.o: Source/%.s
	mkdir -p $(dir $@)
	$(TOOLCHAINBIN)/arm-none-eabi-gcc -mcpu=cortex-m7 -g -c -x assembler-with-cpp -MMD -MP -MF"$(@:.o=.d)" -MT"$@" --specs=nano.specs					\
		-mfpu=fpv5-sp-d16 -mfloat-abi=hard -mthumb -o "$@" "$<"

clean:
	rm -Rf Build

# Include all .d files
-include $(OBJS:%.o=%.d)
