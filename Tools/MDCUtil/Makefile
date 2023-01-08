NAME=MDCUtil
OBJECTS=main.o

CXX			= g++
CXXFLAGS	= -std=c++17 -O0 -g3 -Wall -Weffc++ $(IDIRS)
LFLAGS		= -lusb-1.0

IDIRS =									\
	-iquote ../..						\
	-iquote ../Shared					\
	-iquote ../../Shared				\
	-iquote ../../Code/Lib				\
	-iquote ../../Code/Shared			\
	-iquote ../../Code/STM32/Shared

all: ${OBJECTS}
	$(CXX) $(CXXFLAGS) $? -o $(NAME) $(LFLAGS)

clean:
	rm -Rf *.o $(NAME)
