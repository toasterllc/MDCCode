## About

This repo contains all the firmware / software / Verilog for the [Photon camera](https://toaster.llc/photon).

`MDC` stands for "motion detector camera".

## Repo Organization

`Code/MSP430/MSPApp`: the MSP430 application

`Code/STM32/STLoader`: the STM32 bootloader, which is the default application stored on the STM32's flash

`Code/STM32/STApp`: the STM32 application, which is loaded by the Photon Transfer app when connecting the Photon camera to a Mac

`Code/ICE40/ICEAppMSP`: the top-level ICE40 Verilog that talks to `MSPApp` running on the MSP430

`Tools/MDCStudio`: the Photon Transfer Mac app

`Tools/MDCUtil`: a swiss-army utility for interacting with the Photon camera

