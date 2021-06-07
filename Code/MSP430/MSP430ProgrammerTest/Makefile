OBJECTS=mspprintf.o main.o

GCC_DIR = ~/ti/msp430-gcc/bin
SUPPORT_FILE_DIRECTORY = ~/ti/msp430-gcc/include

DEVICE   = msp430g2553
CC       = $(GCC_DIR)/msp430-elf-gcc
CXX      = $(GCC_DIR)/msp430-elf-g++
GDB      = $(GCC_DIR)/msp430-elf-gdb
MSPDEBUG = ~/repos/mspdebug/mspdebug

CFLAGS   = -I $(SUPPORT_FILE_DIRECTORY) -mmcu=$(DEVICE) -std=c11 -Ofast -g -Wall -Wno-format
CXXFLAGS = -I $(SUPPORT_FILE_DIRECTORY) -mmcu=$(DEVICE) -std=c++17 -Ofast -g -Wall -Wno-format
LFLAGS   = -L $(SUPPORT_FILE_DIRECTORY) -T $(DEVICE).ld -Wl,-Map=$(DEVICE).map

all: ${OBJECTS}
	$(CXX) $(CFLAGS) $(LFLAGS) $? -o $(DEVICE).out

debug: all
	$(GDB) $(DEVICE).out

install: all
	$(MSPDEBUG) rf2500 "prog $(DEVICE).out"
    # $(MSPDEBUG) rf2500 "verify $(DEVICE).out"

clean:
	rm -Rf *.o *.out *.map
