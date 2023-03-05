# CMAKE generated file: DO NOT EDIT!
# Generated by "Unix Makefiles" Generator, CMake Version 3.18

# Delete rule output on recipe failure.
.DELETE_ON_ERROR:


#=============================================================================
# Special targets provided by cmake.

# Disable implicit rules so canonical targets will work.
.SUFFIXES:


# Disable VCS-based implicit rules.
% : %,v


# Disable VCS-based implicit rules.
% : RCS/%


# Disable VCS-based implicit rules.
% : RCS/%,v


# Disable VCS-based implicit rules.
% : SCCS/s.%


# Disable VCS-based implicit rules.
% : s.%


.SUFFIXES: .hpux_make_needs_suffix_list


# Command-line flag to silence nested $(MAKE).
$(VERBOSE)MAKESILENT = -s

#Suppress display of executed commands.
$(VERBOSE).SILENT:

# A target that is always out of date.
cmake_force:

.PHONY : cmake_force

#=============================================================================
# Set environment variables for the build.

# The shell in which to execute make rules.
SHELL = /bin/sh

# The CMake executable.
CMAKE_COMMAND = /usr/local/bin/cmake

# The command to remove a file.
RM = /usr/local/bin/cmake -E rm -f

# Escaping for special characters.
EQUALS = =

# The top-level source directory on which CMake was run.
CMAKE_SOURCE_DIR = /Users/dave/Desktop/BC7Test/bc7enc_rdo

# The top-level build directory on which CMake was run.
CMAKE_BINARY_DIR = /Users/dave/Desktop/BC7Test/bc7enc_rdo

# Include any dependencies generated for this target.
include CMakeFiles/bc7enc.dir/depend.make

# Include the progress variables for this target.
include CMakeFiles/bc7enc.dir/progress.make

# Include the compile flags for this target's objects.
include CMakeFiles/bc7enc.dir/flags.make

bc7e.o: bc7e.ispc
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --blue --bold --progress-dir=/Users/dave/Desktop/BC7Test/bc7enc_rdo/CMakeFiles --progress-num=$(CMAKE_PROGRESS_1) "Generating bc7e.o, bc7e_avx.o, bc7e_sse2.o, bc7e_sse4.o, bc7e_avx2.o"
	ispc -g -O2 /Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7e.ispc -o /Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7e.o -h /Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7e_ispc.h --target=sse2,sse4,avx,avx2 --opt=fast-math --opt=disable-assertions

bc7e_avx.o: bc7e.o
	@$(CMAKE_COMMAND) -E touch_nocreate bc7e_avx.o

bc7e_sse2.o: bc7e.o
	@$(CMAKE_COMMAND) -E touch_nocreate bc7e_sse2.o

bc7e_sse4.o: bc7e.o
	@$(CMAKE_COMMAND) -E touch_nocreate bc7e_sse4.o

bc7e_avx2.o: bc7e.o
	@$(CMAKE_COMMAND) -E touch_nocreate bc7e_avx2.o

CMakeFiles/bc7enc.dir/bc7enc.cpp.o: CMakeFiles/bc7enc.dir/flags.make
CMakeFiles/bc7enc.dir/bc7enc.cpp.o: bc7enc.cpp
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --progress-dir=/Users/dave/Desktop/BC7Test/bc7enc_rdo/CMakeFiles --progress-num=$(CMAKE_PROGRESS_2) "Building CXX object CMakeFiles/bc7enc.dir/bc7enc.cpp.o"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -o CMakeFiles/bc7enc.dir/bc7enc.cpp.o -c /Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7enc.cpp

CMakeFiles/bc7enc.dir/bc7enc.cpp.i: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Preprocessing CXX source to CMakeFiles/bc7enc.dir/bc7enc.cpp.i"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -E /Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7enc.cpp > CMakeFiles/bc7enc.dir/bc7enc.cpp.i

CMakeFiles/bc7enc.dir/bc7enc.cpp.s: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Compiling CXX source to assembly CMakeFiles/bc7enc.dir/bc7enc.cpp.s"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -S /Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7enc.cpp -o CMakeFiles/bc7enc.dir/bc7enc.cpp.s

CMakeFiles/bc7enc.dir/bc7decomp.cpp.o: CMakeFiles/bc7enc.dir/flags.make
CMakeFiles/bc7enc.dir/bc7decomp.cpp.o: bc7decomp.cpp
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --progress-dir=/Users/dave/Desktop/BC7Test/bc7enc_rdo/CMakeFiles --progress-num=$(CMAKE_PROGRESS_3) "Building CXX object CMakeFiles/bc7enc.dir/bc7decomp.cpp.o"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -o CMakeFiles/bc7enc.dir/bc7decomp.cpp.o -c /Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7decomp.cpp

CMakeFiles/bc7enc.dir/bc7decomp.cpp.i: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Preprocessing CXX source to CMakeFiles/bc7enc.dir/bc7decomp.cpp.i"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -E /Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7decomp.cpp > CMakeFiles/bc7enc.dir/bc7decomp.cpp.i

CMakeFiles/bc7enc.dir/bc7decomp.cpp.s: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Compiling CXX source to assembly CMakeFiles/bc7enc.dir/bc7decomp.cpp.s"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -S /Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7decomp.cpp -o CMakeFiles/bc7enc.dir/bc7decomp.cpp.s

CMakeFiles/bc7enc.dir/bc7decomp_ref.cpp.o: CMakeFiles/bc7enc.dir/flags.make
CMakeFiles/bc7enc.dir/bc7decomp_ref.cpp.o: bc7decomp_ref.cpp
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --progress-dir=/Users/dave/Desktop/BC7Test/bc7enc_rdo/CMakeFiles --progress-num=$(CMAKE_PROGRESS_4) "Building CXX object CMakeFiles/bc7enc.dir/bc7decomp_ref.cpp.o"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -o CMakeFiles/bc7enc.dir/bc7decomp_ref.cpp.o -c /Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7decomp_ref.cpp

CMakeFiles/bc7enc.dir/bc7decomp_ref.cpp.i: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Preprocessing CXX source to CMakeFiles/bc7enc.dir/bc7decomp_ref.cpp.i"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -E /Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7decomp_ref.cpp > CMakeFiles/bc7enc.dir/bc7decomp_ref.cpp.i

CMakeFiles/bc7enc.dir/bc7decomp_ref.cpp.s: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Compiling CXX source to assembly CMakeFiles/bc7enc.dir/bc7decomp_ref.cpp.s"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -S /Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7decomp_ref.cpp -o CMakeFiles/bc7enc.dir/bc7decomp_ref.cpp.s

CMakeFiles/bc7enc.dir/lodepng.cpp.o: CMakeFiles/bc7enc.dir/flags.make
CMakeFiles/bc7enc.dir/lodepng.cpp.o: lodepng.cpp
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --progress-dir=/Users/dave/Desktop/BC7Test/bc7enc_rdo/CMakeFiles --progress-num=$(CMAKE_PROGRESS_5) "Building CXX object CMakeFiles/bc7enc.dir/lodepng.cpp.o"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -o CMakeFiles/bc7enc.dir/lodepng.cpp.o -c /Users/dave/Desktop/BC7Test/bc7enc_rdo/lodepng.cpp

CMakeFiles/bc7enc.dir/lodepng.cpp.i: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Preprocessing CXX source to CMakeFiles/bc7enc.dir/lodepng.cpp.i"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -E /Users/dave/Desktop/BC7Test/bc7enc_rdo/lodepng.cpp > CMakeFiles/bc7enc.dir/lodepng.cpp.i

CMakeFiles/bc7enc.dir/lodepng.cpp.s: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Compiling CXX source to assembly CMakeFiles/bc7enc.dir/lodepng.cpp.s"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -S /Users/dave/Desktop/BC7Test/bc7enc_rdo/lodepng.cpp -o CMakeFiles/bc7enc.dir/lodepng.cpp.s

CMakeFiles/bc7enc.dir/test.cpp.o: CMakeFiles/bc7enc.dir/flags.make
CMakeFiles/bc7enc.dir/test.cpp.o: test.cpp
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --progress-dir=/Users/dave/Desktop/BC7Test/bc7enc_rdo/CMakeFiles --progress-num=$(CMAKE_PROGRESS_6) "Building CXX object CMakeFiles/bc7enc.dir/test.cpp.o"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -o CMakeFiles/bc7enc.dir/test.cpp.o -c /Users/dave/Desktop/BC7Test/bc7enc_rdo/test.cpp

CMakeFiles/bc7enc.dir/test.cpp.i: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Preprocessing CXX source to CMakeFiles/bc7enc.dir/test.cpp.i"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -E /Users/dave/Desktop/BC7Test/bc7enc_rdo/test.cpp > CMakeFiles/bc7enc.dir/test.cpp.i

CMakeFiles/bc7enc.dir/test.cpp.s: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Compiling CXX source to assembly CMakeFiles/bc7enc.dir/test.cpp.s"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -S /Users/dave/Desktop/BC7Test/bc7enc_rdo/test.cpp -o CMakeFiles/bc7enc.dir/test.cpp.s

CMakeFiles/bc7enc.dir/rgbcx.cpp.o: CMakeFiles/bc7enc.dir/flags.make
CMakeFiles/bc7enc.dir/rgbcx.cpp.o: rgbcx.cpp
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --progress-dir=/Users/dave/Desktop/BC7Test/bc7enc_rdo/CMakeFiles --progress-num=$(CMAKE_PROGRESS_7) "Building CXX object CMakeFiles/bc7enc.dir/rgbcx.cpp.o"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -o CMakeFiles/bc7enc.dir/rgbcx.cpp.o -c /Users/dave/Desktop/BC7Test/bc7enc_rdo/rgbcx.cpp

CMakeFiles/bc7enc.dir/rgbcx.cpp.i: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Preprocessing CXX source to CMakeFiles/bc7enc.dir/rgbcx.cpp.i"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -E /Users/dave/Desktop/BC7Test/bc7enc_rdo/rgbcx.cpp > CMakeFiles/bc7enc.dir/rgbcx.cpp.i

CMakeFiles/bc7enc.dir/rgbcx.cpp.s: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Compiling CXX source to assembly CMakeFiles/bc7enc.dir/rgbcx.cpp.s"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -S /Users/dave/Desktop/BC7Test/bc7enc_rdo/rgbcx.cpp -o CMakeFiles/bc7enc.dir/rgbcx.cpp.s

CMakeFiles/bc7enc.dir/utils.cpp.o: CMakeFiles/bc7enc.dir/flags.make
CMakeFiles/bc7enc.dir/utils.cpp.o: utils.cpp
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --progress-dir=/Users/dave/Desktop/BC7Test/bc7enc_rdo/CMakeFiles --progress-num=$(CMAKE_PROGRESS_8) "Building CXX object CMakeFiles/bc7enc.dir/utils.cpp.o"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -o CMakeFiles/bc7enc.dir/utils.cpp.o -c /Users/dave/Desktop/BC7Test/bc7enc_rdo/utils.cpp

CMakeFiles/bc7enc.dir/utils.cpp.i: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Preprocessing CXX source to CMakeFiles/bc7enc.dir/utils.cpp.i"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -E /Users/dave/Desktop/BC7Test/bc7enc_rdo/utils.cpp > CMakeFiles/bc7enc.dir/utils.cpp.i

CMakeFiles/bc7enc.dir/utils.cpp.s: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Compiling CXX source to assembly CMakeFiles/bc7enc.dir/utils.cpp.s"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -S /Users/dave/Desktop/BC7Test/bc7enc_rdo/utils.cpp -o CMakeFiles/bc7enc.dir/utils.cpp.s

CMakeFiles/bc7enc.dir/ert.cpp.o: CMakeFiles/bc7enc.dir/flags.make
CMakeFiles/bc7enc.dir/ert.cpp.o: ert.cpp
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --progress-dir=/Users/dave/Desktop/BC7Test/bc7enc_rdo/CMakeFiles --progress-num=$(CMAKE_PROGRESS_9) "Building CXX object CMakeFiles/bc7enc.dir/ert.cpp.o"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -o CMakeFiles/bc7enc.dir/ert.cpp.o -c /Users/dave/Desktop/BC7Test/bc7enc_rdo/ert.cpp

CMakeFiles/bc7enc.dir/ert.cpp.i: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Preprocessing CXX source to CMakeFiles/bc7enc.dir/ert.cpp.i"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -E /Users/dave/Desktop/BC7Test/bc7enc_rdo/ert.cpp > CMakeFiles/bc7enc.dir/ert.cpp.i

CMakeFiles/bc7enc.dir/ert.cpp.s: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Compiling CXX source to assembly CMakeFiles/bc7enc.dir/ert.cpp.s"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -S /Users/dave/Desktop/BC7Test/bc7enc_rdo/ert.cpp -o CMakeFiles/bc7enc.dir/ert.cpp.s

CMakeFiles/bc7enc.dir/rdo_bc_encoder.cpp.o: CMakeFiles/bc7enc.dir/flags.make
CMakeFiles/bc7enc.dir/rdo_bc_encoder.cpp.o: rdo_bc_encoder.cpp
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --progress-dir=/Users/dave/Desktop/BC7Test/bc7enc_rdo/CMakeFiles --progress-num=$(CMAKE_PROGRESS_10) "Building CXX object CMakeFiles/bc7enc.dir/rdo_bc_encoder.cpp.o"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -o CMakeFiles/bc7enc.dir/rdo_bc_encoder.cpp.o -c /Users/dave/Desktop/BC7Test/bc7enc_rdo/rdo_bc_encoder.cpp

CMakeFiles/bc7enc.dir/rdo_bc_encoder.cpp.i: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Preprocessing CXX source to CMakeFiles/bc7enc.dir/rdo_bc_encoder.cpp.i"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -E /Users/dave/Desktop/BC7Test/bc7enc_rdo/rdo_bc_encoder.cpp > CMakeFiles/bc7enc.dir/rdo_bc_encoder.cpp.i

CMakeFiles/bc7enc.dir/rdo_bc_encoder.cpp.s: cmake_force
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green "Compiling CXX source to assembly CMakeFiles/bc7enc.dir/rdo_bc_encoder.cpp.s"
	/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/c++ $(CXX_DEFINES) $(CXX_INCLUDES) $(CXX_FLAGS) -S /Users/dave/Desktop/BC7Test/bc7enc_rdo/rdo_bc_encoder.cpp -o CMakeFiles/bc7enc.dir/rdo_bc_encoder.cpp.s

# Object files for target bc7enc
bc7enc_OBJECTS = \
"CMakeFiles/bc7enc.dir/bc7enc.cpp.o" \
"CMakeFiles/bc7enc.dir/bc7decomp.cpp.o" \
"CMakeFiles/bc7enc.dir/bc7decomp_ref.cpp.o" \
"CMakeFiles/bc7enc.dir/lodepng.cpp.o" \
"CMakeFiles/bc7enc.dir/test.cpp.o" \
"CMakeFiles/bc7enc.dir/rgbcx.cpp.o" \
"CMakeFiles/bc7enc.dir/utils.cpp.o" \
"CMakeFiles/bc7enc.dir/ert.cpp.o" \
"CMakeFiles/bc7enc.dir/rdo_bc_encoder.cpp.o"

# External object files for target bc7enc
bc7enc_EXTERNAL_OBJECTS = \
"/Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7e.o" \
"/Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7e_avx.o" \
"/Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7e_avx2.o" \
"/Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7e_sse2.o" \
"/Users/dave/Desktop/BC7Test/bc7enc_rdo/bc7e_sse4.o"

bc7enc: CMakeFiles/bc7enc.dir/bc7enc.cpp.o
bc7enc: CMakeFiles/bc7enc.dir/bc7decomp.cpp.o
bc7enc: CMakeFiles/bc7enc.dir/bc7decomp_ref.cpp.o
bc7enc: CMakeFiles/bc7enc.dir/lodepng.cpp.o
bc7enc: CMakeFiles/bc7enc.dir/test.cpp.o
bc7enc: CMakeFiles/bc7enc.dir/rgbcx.cpp.o
bc7enc: CMakeFiles/bc7enc.dir/utils.cpp.o
bc7enc: CMakeFiles/bc7enc.dir/ert.cpp.o
bc7enc: CMakeFiles/bc7enc.dir/rdo_bc_encoder.cpp.o
bc7enc: bc7e.o
bc7enc: bc7e_avx.o
bc7enc: bc7e_avx2.o
bc7enc: bc7e_sse2.o
bc7enc: bc7e_sse4.o
bc7enc: CMakeFiles/bc7enc.dir/build.make
bc7enc: CMakeFiles/bc7enc.dir/link.txt
	@$(CMAKE_COMMAND) -E cmake_echo_color --switch=$(COLOR) --green --bold --progress-dir=/Users/dave/Desktop/BC7Test/bc7enc_rdo/CMakeFiles --progress-num=$(CMAKE_PROGRESS_11) "Linking CXX executable bc7enc"
	$(CMAKE_COMMAND) -E cmake_link_script CMakeFiles/bc7enc.dir/link.txt --verbose=$(VERBOSE)

# Rule to build all files generated by this target.
CMakeFiles/bc7enc.dir/build: bc7enc

.PHONY : CMakeFiles/bc7enc.dir/build

CMakeFiles/bc7enc.dir/clean:
	$(CMAKE_COMMAND) -P CMakeFiles/bc7enc.dir/cmake_clean.cmake
.PHONY : CMakeFiles/bc7enc.dir/clean

CMakeFiles/bc7enc.dir/depend: bc7e.o
CMakeFiles/bc7enc.dir/depend: bc7e_avx.o
CMakeFiles/bc7enc.dir/depend: bc7e_sse2.o
CMakeFiles/bc7enc.dir/depend: bc7e_sse4.o
CMakeFiles/bc7enc.dir/depend: bc7e_avx2.o
	cd /Users/dave/Desktop/BC7Test/bc7enc_rdo && $(CMAKE_COMMAND) -E cmake_depends "Unix Makefiles" /Users/dave/Desktop/BC7Test/bc7enc_rdo /Users/dave/Desktop/BC7Test/bc7enc_rdo /Users/dave/Desktop/BC7Test/bc7enc_rdo /Users/dave/Desktop/BC7Test/bc7enc_rdo /Users/dave/Desktop/BC7Test/bc7enc_rdo/CMakeFiles/bc7enc.dir/DependInfo.cmake --color=$(COLOR)
.PHONY : CMakeFiles/bc7enc.dir/depend

