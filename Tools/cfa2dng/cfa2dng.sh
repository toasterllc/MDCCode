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

./exiftool -overwrite_original -all= $dng

./exiftool                                              \
    -DNGVersion="1.4.0.0"                               \
    -DNGBackwardVersion="1.4.0.0"                       \
    -ColorMatrix1="1 0 0 0 1 0 0 0 1"                   \
    -CalibrationIlluminant1=D65                         \
    -IFD0:BlackLevel=0                                  \
    -IFD0:WhiteLevel=65535                              \
    -PhotometricInterpretation="Color Filter Array"     \
    -SamplesPerPixel=1                                  \
    -IFD0:CFARepeatPatternDim="2 2"                     \
    -IFD0:CFAPattern2="1 0 2 1"                         \
    -overwrite_original                                 \
    "$dng"


# ./exiftool                                              \
#     -DNGVersion="1.1.0.0"                               \
#     -DNGBackwardVersion="1.1.0.0"                       \
#     -ColorMatrix1="1 0 0 0 1 0 0 0 1"                   \
#     -ColorMatrix2="1 0 0 0 1 0 0 0 1"                   \
#     -CameraCalibration1="1 0 0 0 1 0 0 0 1"             \
#     -CameraCalibration2="1 0 0 0 1 0 0 0 1"             \
#     -CalibrationIlluminant1=D65                         \
#     -CalibrationIlluminant2=D65                         \
#     -AnalogBalance="1 1 1"                              \
#     -AsShotWhiteXY="0.31271 0.32902"                    \
#     -IFD0:BlackLevel=0                                  \
#     -IFD0:WhiteLevel=65535                              \
#     -PhotometricInterpretation="Color Filter Array"     \
#     -SamplesPerPixel=1                                  \
#     -IFD0:CFARepeatPatternDim="2 2"                     \
#     -IFD0:CFAPattern2="1 0 2 1"                         \
#     -overwrite_original                                 \
#     "$dng"                                              \


    # -AsShotNeutral="1 1"                                \
    # -AsShotWhiteXY="0.31271 0.32902"                    \



# ./exiftool                                              \
#     -DNGVersion="1.4.0.0"                               \
#     -DNGBackwardVersion="1.4.0.0"                       \
#     -ColorMatrix1="1 0 0 0 1 0 0 0 1"                   \
#     -ColorMatrix2="1 0 0 0 1 0 0 0 1"                   \
#     -CameraCalibration1="1 0 0 0 1 0 0 0 1"             \
#     -CameraCalibration2="1 0 0 0 1 0 0 0 1"             \
#     -ForwardMatrix1="1 0 0 0 1 0 0 0 1"                 \
#     -ForwardMatrix2="1 0 0 0 1 0 0 0 1"                 \
#     -CalibrationIlluminant1=D50                         \
#     -CalibrationIlluminant2=D50                         \
#     -AsShotNeutral="0.34567 0.35850"                    \
#     -AnalogBalance="1 1 1"                              \
#     -IFD0:BlackLevel=0                                  \
#     -IFD0:WhiteLevel=65535                              \
#     -PhotometricInterpretation="Color Filter Array"     \
#     -SamplesPerPixel=1                                  \
#     -IFD0:CFARepeatPatternDim="2 2"                     \
#     -IFD0:CFAPattern2="1 0 2 1"                         \
#     -overwrite_original                                 \
#     "$dng"                                              \

        
# ./exiftool                                              \
#     -DNGVersion="1.4.0.0"                               \
#     -DNGBackwardVersion="1.4.0.0"                       \
#     -ColorMatrix1="1 0 0 0 1 0 0 0 1"                   \
#     -ForwardMatrix1="1 0 0 0 1 0 0 0 1"                 \
#     -CameraCalibration1="1 0 0 0 1 0 0 0 1"             \
#     -CalibrationIlluminant1=D65                         \
#     -ColorMatrix2="1 0 0 0 1 0 0 0 1"                   \
#     -ForwardMatrix2="1 0 0 0 1 0 0 0 1"                 \
#     -CameraCalibration2="1 0 0 0 1 0 0 0 1"             \
#     -CalibrationIlluminant2=D65                         \
#     -AnalogBalance="1 1 1"                              \
#     -IFD0:BlackLevel=0                                  \
#     -IFD0:WhiteLevel=65535                              \
#     -PhotometricInterpretation="Color Filter Array"     \
#     -SamplesPerPixel=1                                  \
#     -IFD0:CFARepeatPatternDim="2 2"                     \
#     -IFD0:CFAPattern2="1 0 2 1"                         \
#     -overwrite_original                                 \
#     "$dng"                                              \
#


        

           
           
# -ColorMatrix1="0.320823 -0.0917411 -0.0415002 0.0267526 0.209594 0.00708195 0.0235916 0.0333623 0.085843"           \




#    -ColorMatrix1="1 0 0 0 1 0 0 0 1"                                                                       \
#    -ColorMatrix1="4.434985 -1.874714 1.567622 -0.021370 1.589914 1.099316 0.953972 -2.506772 6.637731"     \
#    -ColorMatrix1="4.434985 -0.021370 0.953972 -1.874714 1.589914 -2.506772 1.567622 1.099316 6.637731"     \


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
