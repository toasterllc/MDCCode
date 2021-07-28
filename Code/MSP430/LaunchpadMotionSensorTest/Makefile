OBJECTS=main.o

GCC_DIR = ~/ti/msp430-gcc/bin
SUPPORT_FILE_DIRECTORY = ~/ti/msp430-gcc/include

DEVICE   = msp430g2553
CC       = $(GCC_DIR)/msp430-elf-gcc
CXX      = $(GCC_DIR)/msp430-elf-g++
GDB      = $(GCC_DIR)/msp430-elf-gdb
MSPDEBUG = ~/repos/mspdebug/mspdebug

CFLAGS   = -I $(SUPPORT_FILE_DIRECTORY) -mmcu=$(DEVICE) -O0 -g -Wall -std=c11
CXXFLAGS = -I $(SUPPORT_FILE_DIRECTORY) -mmcu=$(DEVICE) -O0 -g -Wall -std=c++17
LFLAGS   = -L $(SUPPORT_FILE_DIRECTORY) -T $(DEVICE).ld -Wl,-Map=$(DEVICE).map

all: ${OBJECTS}
	$(CXX) $(CFLAGS) $(LFLAGS) $? -o $(DEVICE).elf

debug: all
	$(GDB) $(DEVICE).elf

install: all
	$(MSPDEBUG) rf2500 "prog $(DEVICE).elf"
	$(MSPDEBUG) rf2500 "verify $(DEVICE).elf"

clean:
	rm -Rf *.o *.elf *.map
