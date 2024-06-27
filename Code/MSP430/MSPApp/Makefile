OUTPUT := MSPApp.elf
BUILDDIR := Build
TOOLCHAIN := "../../../Tools/gcc-msp430"
TOOLCHAINSETUP := $(shell $(TOOLCHAIN)/setup.sh) # Prepare toolchain
TOOLCHAINBIN := $(TOOLCHAIN)/platform/bin

SRCS := $(shell find . -name '*.cpp')
OBJS := $(addprefix $(BUILDDIR)/, $(addsuffix .o, $(basename $(SRCS))))

INCLUDES :=					\
	-I$(TOOLCHAIN)/include	\
	-I"."					\
	-I"../../.."

# Link final product
$(BUILDDIR)/$(OUTPUT): $(OBJS)
	$(TOOLCHAINBIN)/msp430-elf-gcc -mhwmult=f5series -fno-exceptions -Os -ffunction-sections			\
		-fdata-sections -g -gdwarf-4 -Wall -flto -mmcu=msp430fr2433 -Wl,-Map,"$(@:.elf=.map)"			\
		-nostartfiles -static -Wl,--gc-sections -mmcu=msp430fr2433 -L$(TOOLCHAIN)/include				\
		-Wl,-flto -o $@ -T'msp430fr2433.ld' -T'Linker.ld' -Wl,--start-group -lgcc -lc					\
		-Wl,--end-group $(OBJS)

# C++ rules
$(BUILDDIR)/%.o: %.cpp
	mkdir -p $(dir $@)
	$(TOOLCHAINBIN)/msp430-elf-gcc $(INCLUDES) -c -mmcu=msp430fr2433 -mhwmult=f5series -fno-exceptions	\
		-Os -ffunction-sections -fdata-sections -g -gdwarf-4 -Wall -flto -MMD -MP						\
		-MF"$(@:.o=.d)" -MT"$@" -std=c++17 -fno-rtti -fno-threadsafe-statics				\
		-o"$@" "$<"

clean:
	rm -rf $(BUILDDIR)

# Include all .d files
-include $(OBJS:%.o=%.d)
