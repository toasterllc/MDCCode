BUILDDIR := Build
TOOLCHAIN := "../../../Tools/gcc-stm32"
TOOLCHAINSETUP := $(shell $(TOOLCHAIN)/setup.sh) # Prepare toolchain
TOOLCHAINBIN := $(TOOLCHAIN)/platform/bin

SRCS := $(shell find Source -name '*.cpp' -o -name '*.s')			\
		$(shell cd ..; find Shared -name '*.cpp' -o -name '*.s')

OBJS := $(addprefix $(BUILDDIR)/, $(addsuffix .o, $(basename $(SRCS))))

# Link final product
$(BUILDDIR)/$(OUTPUT): $(OBJS)
	$(TOOLCHAINBIN)/arm-none-eabi-g++ -o $@ $(OBJS) -mcpu=cortex-m7 -T'Linker.ld' -Wl,-Map=$(BUILDDIR)/$(OUTPUT:.elf=.map)	\
		-Wl,--gc-sections -static -L../Shared --specs=nano.specs -mfpu=fpv5-sp-d16 -mfloat-abi=hard -mthumb								\
		-Wl,--start-group -lc -lm -lstdc++ -lsupc++ -Wl,--end-group -Wl,--no-warn-rwx-segments

# C++ rules
$(BUILDDIR)/Shared/%.o: ../Shared/%.cpp
	mkdir -p $(dir $@)
	$(TOOLCHAINBIN)/arm-none-eabi-g++ "$<" -mcpu=cortex-m7 -std=c++17 -g3 -DUSE_HAL_DRIVER -DSTM32F730xx -c -Os -ffunction-sections -fdata-sections		\
		-fno-exceptions -fno-rtti -fno-threadsafe-statics -fno-use-cxa-atexit -Wall -std=c++1z -iquote '../../..'						\
		-iquote '../Shared' -iquote '../Shared/ST' -iquote 'Source' -fstack-usage -MMD -MP -MF"$(@:.o=.d)" -MT"$@"						\
		--specs=nano.specs -mfpu=fpv5-sp-d16 -mfloat-abi=hard -mthumb -o "$@"

$(BUILDDIR)/Source/%.o: Source/%.cpp
	mkdir -p $(dir $@)
	$(TOOLCHAINBIN)/arm-none-eabi-g++ "$<" -mcpu=cortex-m7 -std=c++17 -g3 -DUSE_HAL_DRIVER -DSTM32F730xx -c -Os -ffunction-sections -fdata-sections		\
		-fno-exceptions -fno-rtti -fno-threadsafe-statics -fno-use-cxa-atexit -Wall -std=c++1z -iquote '../../..'						\
		-iquote '../Shared' -iquote '../Shared/ST' -iquote 'Source' -fstack-usage -MMD -MP -MF"$(@:.o=.d)" -MT"$@"						\
		--specs=nano.specs -mfpu=fpv5-sp-d16 -mfloat-abi=hard -mthumb -o "$@"

# Assembly rule
$(BUILDDIR)/Shared/%.o: ../Shared/%.s
	mkdir -p $(dir $@)
	$(TOOLCHAINBIN)/arm-none-eabi-gcc -mcpu=cortex-m7 -g -c -x assembler-with-cpp -MMD -MP -MF"$(@:.o=.d)" -MT"$@" --specs=nano.specs					\
		-mfpu=fpv5-sp-d16 -mfloat-abi=hard -mthumb -o "$@" "$<"

clean:
	rm -Rf Build

# Include all .d files
-include $(OBJS:%.o=%.d)
