#!/bin/bash
set -e

if [ "$#" -ne 2 ]; then
	echo "Usage:"
    echo "  cfa2dng.sh <InputName.cfa> <OutputName.dng>"
	exit 1
fi

cfa=$1
dng=$2

./cfa2dng "$cfa" "$dng"

# BlackLevel=0
./exiftool                                                      \
    -DNGVersion="1.4.0.0"                                       \
    -DNGBackwardVersion="1.4.0.0"                               \
    -ColorMatrix1="1 0 0 0 1 0 0 0 1"                           \
    -IFD0:BlackLevel=0                                          \
    -IFD0:WhiteLevel=4095                                       \
    -PhotometricInterpretation="Color Filter Array"             \
    -SamplesPerPixel=1                                          \
    -IFD0:CFARepeatPatternDim="2 2"                             \
    -IFD0:CFAPattern2="1 0 2 1"                                 \
    -overwrite_original                                         \
    "$dng"                                                      \

# # BlackLevel=512
# ./exiftool                                                      \
#     -DNGVersion="1.4.0.0"                                       \
#     -DNGBackwardVersion="1.4.0.0"                               \
#     -ColorMatrix1="1.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 1.0"         \
#     -IFD0:BlackLevel=512                                        \
#     -IFD0:WhiteLevel=4095                                       \
#     -PhotometricInterpretation="Color Filter Array"             \
#     -CalibrationIlluminant1=D65                                 \
#     -SamplesPerPixel=1                                          \
#     -IFD0:CFARepeatPatternDim="2 2"                             \
#     -IFD0:CFAPattern2="1 0 2 1"                                 \
    # "$dng"                                                      \

./exiftool "$dng"
