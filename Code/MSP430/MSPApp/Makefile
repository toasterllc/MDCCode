OBJECTS=main.o

GCC_DIR = ~/ti/msp430-gcc/bin
SUPPORT_FILE_DIRECTORY = ~/ti/msp430-gcc/include
SHARED_SRC_DIR = ../../Shared

DEVICE   = msp430fr2422
CC       = $(GCC_DIR)/msp430-elf-gcc
CXX      = $(GCC_DIR)/msp430-elf-g++
GDB      = $(GCC_DIR)/msp430-elf-gdb
MSPDEBUG = ~/repos/mspdebug/mspdebug

CXXFLAGS = -I $(SUPPORT_FILE_DIRECTORY) -I $(SHARED_SRC_DIR) -mmcu=$(DEVICE) -O0 -g -Wall -std=c++17
LFLAGS   = -L $(SUPPORT_FILE_DIRECTORY) -T $(DEVICE).ld -Wl,-Map=$(DEVICE).map

all: ${OBJECTS}
	$(CXX) $(CXXFLAGS) $(LFLAGS) $? -o $(DEVICE).elf

debug: all
	$(GDB) $(DEVICE).elf

install: all
	$(MSPDEBUG) rf2500 "prog $(DEVICE).elf"
	$(MSPDEBUG) rf2500 "verify $(DEVICE).elf"

clean:
	rm -Rf *.o *.elf *.map
