OBJECTS=main.o

GCC_DIR = ~/ti/msp430-gcc/bin
SUPPORT_FILE_DIRECTORY = ~/ti/msp430-gcc/include

DEVICE   = msp430fr2433
CC       = $(GCC_DIR)/msp430-elf-gcc
CXX      = $(GCC_DIR)/msp430-elf-g++
GDB      = $(GCC_DIR)/msp430-elf-gdb
MSPDEBUG = LD_LIBRARY_PATH=~/repos/mspdebug ~/repos/mspdebug/mspdebug

CFLAGS   = -I $(SUPPORT_FILE_DIRECTORY) -mmcu=$(DEVICE) -O0 -g -Wall -std=c11
CXXFLAGS = -I $(SUPPORT_FILE_DIRECTORY) -mmcu=$(DEVICE) -O0 -g -Wall -std=c++17
LFLAGS   = -L $(SUPPORT_FILE_DIRECTORY) -T $(DEVICE).ld -T Linker.ld -Wl,-Map=$(DEVICE).map

all: ${OBJECTS}
	$(CXX) $(CFLAGS) $(LFLAGS) $? -o $(DEVICE).elf

debug: all
	$(GDB) $(DEVICE).elf

install: all
	$(MSPDEBUG) tilib "prog $(DEVICE).elf"
    # $(MSPDEBUG) tilib "verify $(DEVICE).elf"

clean:
	rm -Rf *.o *.elf *.map
