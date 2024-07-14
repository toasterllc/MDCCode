#/bin/bash
set -e

if [ "$#" -ne 2 ]; then
	echo "Usage:"
    echo "  STM32-Printf-Buffer.sh <bufferAddr> <bufferSize>"
	exit 1
fi

bufferAddr=$(($1))
bufferSize=$(($2))
lines=$(((bufferSize/16)+1))

data=$(/Volumes/STM32CubeIDE/STM32CubeIDE.app/Contents/Eclipse/plugins/com.st.stm32cube.ide.mcu.externaltools.cubeprogrammer.macos64_2.1.400.202404281720/tools/bin/STM32_Programmer_CLI -c port=swd -r8 "$bufferAddr" "$bufferSize")

echo "$data" | tail "-$lines" | awk '!($1=$2="")' | xxd -r -p
