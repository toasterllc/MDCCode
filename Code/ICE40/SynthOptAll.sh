#!/bin/bash
set -e

if [ "$#" -ne 1 ]; then
    echo "Usage:"
    echo "  SynthOptAll.sh <OptimizeIterations>"
    exit 1
fi

optIter="$1"

./Synth.py --dev hx8k --pkg bg121:4k --proj ICEAppMSP --opt "$optIter"
./Synth.py --dev hx8k --pkg bg121:4k --proj ICEAppSDReadoutSTM --opt "$optIter"
./Synth.py --dev hx8k --pkg bg121:4k --proj ICEAppImgCaptureSTM --opt "$optIter"

cat ICEAppMSP/NextpnrArgs.py            | grep '# ' | sed -e 's/# //g'
echo

cat ICEAppSDReadoutSTM/NextpnrArgs.py   | grep '# ' | sed -e 's/# //g'
echo

cat ICEAppImgCaptureSTM/NextpnrArgs.py  | grep '# ' | sed -e 's/# //g'
echo
