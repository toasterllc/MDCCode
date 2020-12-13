#!/bin/bash
set -e

if [ "$#" -ne 1 ]; then
	echo "Usage:"
    echo "  cfa2dng.sh <ImageName>"
	exit 1
fi

img=$1

./cfa2dng "$img".cfa "$img".tiff
cp "$img".tiff "$img".dng

# BlackLevel=0
./exiftool                                                      \
    -DNGVersion="1.4.0.0"                                       \
    -DNGBackwardVersion="1.4.0.0"                               \
    -ColorMatrix1="1.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 1.0"         \
    -IFD0:BlackLevel=0                                          \
    -IFD0:WhiteLevel=4095                                       \
    -PhotometricInterpretation="Color Filter Array"             \
    -CalibrationIlluminant1=D65                                 \
    -SamplesPerPixel=1                                          \
    -IFD0:CFARepeatPatternDim="2 2"                             \
    -IFD0:CFAPattern2="1 0 2 1"                                 \
    "$img".dng                                                  \

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
#     "$img".dng                                                  \


./exiftool "$img".dng
