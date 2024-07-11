OUTPUT := STMThumbdrive.elf
BUILDDIR := Build
TOOLCHAIN := "../../../Tools/gcc-stm32"
TOOLCHAINSETUP := $(shell $(TOOLCHAIN)/setup.sh) # Prepare toolchain
TOOLCHAINBIN := $(TOOLCHAIN)/platform/bin

SRCS := $(shell find Source -name '*.c' -o -name '*.cpp' -o -name '*.s')

OBJS := $(addprefix $(BUILDDIR)/, $(addsuffix .o, $(basename $(SRCS))))

INCS :=																		\
	-iquote '../../..'														\
	-iquote '../Shared'														\
	-iquote 'Source'														\
	-iquote 'Source/FATFS'													\
	-iquote 'Source/ST'														\
	-iquote 'Source/USB'													\



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

# C++ rules
$(BUILDDIR)/Source/%.o: Source/%.cpp
	mkdir -p $(dir $@)
	$(TOOLCHAINBIN)/arm-none-eabi-g++ "$<" -mcpu=cortex-m7 -std=c++17 -g3 -DUSE_HAL_DRIVER -DSTM32F730xx -c -Os -ffunction-sections -fdata-sections		\
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
