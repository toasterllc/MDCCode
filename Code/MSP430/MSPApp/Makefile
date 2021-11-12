OBJECTS=main.o

GCC_DIR = ~/ti/msp430-gcc/bin
SUPPORT_FILE_DIRECTORY = ~/ti/msp430-gcc/include

DEVICE   = msp430fr2422
CXX      = $(GCC_DIR)/msp430-elf-g++
GDB      = $(GCC_DIR)/msp430-elf-gdb
MSPDEBUG = ~/repos/mspdebug/mspdebug

CXXFLAGS = -I $(SUPPORT_FILE_DIRECTORY) -mmcu=$(DEVICE) -Os -g -Wall -std=c++17 $(IDIRS)
LFLAGS   = -L $(SUPPORT_FILE_DIRECTORY) -T $(DEVICE).ld -Wl,-Map=$(DEVICE).map
IDIRS    = -iquote ../../Shared     \
           -iquote ../../Lib

all: ${OBJECTS}
	$(CXX) $(CXXFLAGS) $(LFLAGS) $? -o $(DEVICE).elf

debug: all
	$(GDB) $(DEVICE).elf

install: all
	$(MSPDEBUG) rf2500 "prog $(DEVICE).elf"
	$(MSPDEBUG) rf2500 "verify $(DEVICE).elf"

clean:
	rm -Rf *.o *.elf *.map
