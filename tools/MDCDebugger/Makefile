NAME        = MDCDebugger
OBJECTS     = MDCDebugger.o
CXX         = g++
CXXFLAGS    = -O2 -g -Wall -Wno-narrowing -std=c++17
LFLAGS      = -lftdi1

all: ${OBJECTS}
	$(CXX) $? $(CXXFLAGS) $(LFLAGS) -o $(NAME)

clean:
	rm -Rf *.o $(NAME)
