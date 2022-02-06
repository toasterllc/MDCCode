#!/bin/bash
set -e

./Synth.py --dev hx8k --pkg bg121:4k --proj ICEAppMSP --opt
./Synth.py --dev hx8k --pkg bg121:4k --proj ICEAppSDReadoutSTM --opt
./Synth.py --dev hx8k --pkg bg121:4k --proj ICEAppImgCaptureSTM --opt

cat ICEAppMSP/NextpnrArgs.py            | grep '# ' | sed -e 's/# //g'
echo

cat ICEAppSDReadoutSTM/NextpnrArgs.py   | grep '# ' | sed -e 's/# //g'
echo

cat ICEAppImgCaptureSTM/NextpnrArgs.py  | grep '# ' | sed -e 's/# //g'
echo
