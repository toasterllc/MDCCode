#/bin/bash

/Volumes/STM32CubeIDE/STM32CubeIDE.app/Contents/Eclipse/plugins/com.st.stm32cube.ide.mcu.externaltools.cubeprogrammer.macos64_2.1.400.202404281720/tools/bin/STM32_Programmer_CLI -c port=swd -r8 0x20000000 1024 | tail -65 | awk '!($1=$2="")'  | xxd -r -p
