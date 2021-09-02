`ifndef ICEAppTypes_v
`define ICEAppTypes_v

`define Msg_Len                                                 64

`define Msg_Type_Len                                            8
`define Msg_Type_Bits                                           63:56

`define Msg_Type_StartBit                                       `Msg_Type_Len'h80 // Signals start of a new message
`define     Msg_Type_StartBit_Bits                              7:7

`define Msg_Type_Resp                                           `Msg_Type_Len'h40 // Response sent
`define     Msg_Type_Resp_Bits                                  6:6

`define Msg_Arg_Len                                             56
`define Msg_Arg_Bits                                            55:0

`define Resp_Len                                                `Msg_Len
`define Resp_Arg_Bits                                           63:0

`define Msg_Type_Echo                                           `Msg_Type_StartBit | `Msg_Type_Resp | `Msg_Type_Len'h00
`define     Msg_Arg_Echo_Msg_Len                                56
`define     Msg_Arg_Echo_Msg_Bits                               55:0
`define     Resp_Arg_Echo_Msg_Bits                              63:8

`define Msg_Type_LEDSet                                         `Msg_Type_StartBit | `Msg_Type_Len'h01
`define     Msg_Arg_LEDSet_Val_Len                              4
`define     Msg_Arg_LEDSet_Val_Bits                             3:0

`define Msg_Type_SDInit                                         `Msg_Type_StartBit | `Msg_Type_Len'h02
`define     Msg_Arg_SDInit_Clk_Delay_Len                        4
`define     Msg_Arg_SDInit_Clk_Delay_Bits                       7:4
`define     Msg_Arg_SDInit_Clk_Speed_Len                        2
`define     Msg_Arg_SDInit_Clk_Speed_Bits                       3:2
`define     Msg_Arg_SDInit_Trigger_Len                          1
`define     Msg_Arg_SDInit_Trigger_Bits                         1:1
`define     Msg_Arg_SDInit_Reset_Len                            1
`define     Msg_Arg_SDInit_Reset_Bits                           0:0

`define Msg_Type_SDSendCmd                                      `Msg_Type_StartBit | `Msg_Type_Len'h03
`define     Msg_Arg_SDSendCmd_RespType_Len                      2
`define     Msg_Arg_SDSendCmd_RespType_Bits                     51:50
`define     Msg_Arg_SDSendCmd_RespType_136                      `Msg_Arg_SDSendCmd_RespType_Len'b10
`define     Msg_Arg_SDSendCmd_RespType_48                       `Msg_Arg_SDSendCmd_RespType_Len'b01
`define     Msg_Arg_SDSendCmd_RespType_None                     `Msg_Arg_SDSendCmd_RespType_Len'b00
`define     Msg_Arg_SDSendCmd_DatInType_Len                     2
`define     Msg_Arg_SDSendCmd_DatInType_Bits                    49:48
`define     Msg_Arg_SDSendCmd_DatInType_Nx4096                  `Msg_Arg_SDSendCmd_DatInType_Len'b10
`define     Msg_Arg_SDSendCmd_DatInType_1x512                   `Msg_Arg_SDSendCmd_DatInType_Len'b01
`define     Msg_Arg_SDSendCmd_DatInType_None                    `Msg_Arg_SDSendCmd_DatInType_Len'b00
`define     Msg_Arg_SDSendCmd_CmdData_Bits                      47:0

`define Msg_Type_SDStatus                                       `Msg_Type_StartBit | `Msg_Type_Resp | `Msg_Type_Len'h04
`define     Resp_Arg_SDStatus_CmdDone_Bits                      63:63
`define     Resp_Arg_SDStatus_RespDone_Bits                     62:62
`define         Resp_Arg_SDStatus_RespCRCErr_Bits               61:61
`define         Resp_Arg_SDStatus_Resp_Bits                     60:13
`define         Resp_Arg_SDStatus_Resp_Len                      48
`define     Resp_Arg_SDStatus_DatOutDone_Bits                   12:12
`define         Resp_Arg_SDStatus_DatOutCRCErr_Bits             11:11
`define     Resp_Arg_SDStatus_DatInDone_Bits                    10:10
`define         Resp_Arg_SDStatus_DatInCRCErr_Bits              9:9
`define         Resp_Arg_SDStatus_DatInCMD6AccessMode_Bits      8:5
`define     Resp_Arg_SDStatus_Dat0Idle_Bits                     4:4

`define Msg_Type_SDReadout                                      `Msg_Type_StartBit | `Msg_Type_Len'h05

`define Msg_Type_ImgReset                                       `Msg_Type_StartBit | `Msg_Type_Len'h06
`define     Msg_Arg_ImgReset_Val_Bits                           0:0

`define Msg_Type_ImgSetHeader1                                  `Msg_Type_StartBit | `Msg_Type_Len'h07
`define     Msg_Arg_ImgSetHeader1_Header_Bits                   55:0

`define Msg_Type_ImgSetHeader2                                  `Msg_Type_StartBit | `Msg_Type_Len'h08
`define     Msg_Arg_ImgSetHeader2_Header_Bits                   55:0

`define Msg_Type_ImgCapture                                     `Msg_Type_StartBit | `Msg_Type_Len'h09
`define     Msg_Arg_ImgCapture_DstBlock_Bits                    2:0 // Wider than currently necessary to future-proof

`define Msg_Type_ImgCaptureStatus                               `Msg_Type_StartBit | `Msg_Type_Resp | `Msg_Type_Len'h0A
`define     Resp_Arg_ImgCaptureStatus_Done_Bits                 63:63
`define     Resp_Arg_ImgCaptureStatus_WordCount_Bits            62:39
`define     Resp_Arg_ImgCaptureStatus_HighlightCount_Bits       38:21
`define     Resp_Arg_ImgCaptureStatus_ShadowCount_Bits          20:3

`define Msg_Type_ImgReadout                                     `Msg_Type_StartBit | `Msg_Type_Len'h0B
`define     Msg_Arg_ImgReadout_DstBlock_Bits                    2:0 // Wider than currently necessary to future-proof

`define Msg_Type_ImgI2CTransaction                              `Msg_Type_StartBit | `Msg_Type_Len'h0C
`define     Msg_Arg_ImgI2CTransaction_Write_Bits                55:55
`define     Msg_Arg_ImgI2CTransaction_DataLen_Bits              54:54
`define         Msg_Arg_ImgI2CTransaction_DataLen_1             1'b0
`define         Msg_Arg_ImgI2CTransaction_DataLen_2             1'b1
`define     Msg_Arg_ImgI2CTransaction_RegAddr_Bits              31:16
`define     Msg_Arg_ImgI2CTransaction_WriteData_Bits            15:0

`define Msg_Type_ImgI2CStatus                                   `Msg_Type_StartBit | `Msg_Type_Resp | `Msg_Type_Len'h0D
`define     Resp_Arg_ImgI2CStatus_Done_Bits                     63:63
`define     Resp_Arg_ImgI2CStatus_Err_Bits                      62:62
`define     Resp_Arg_ImgI2CStatus_ReadData_Bits                 61:46

`define Msg_Type_Nop                                            `Msg_Type_Len'h00

// `ifdef SIM
// localparam ImageWidthMax = 64;
// localparam ImageHeightMax = 1;
// `else
// localparam ImageWidthMax = 2304;
// localparam ImageHeightMax = 1296+2; // +2 rows for embedded statistics (histogram)
// `endif

localparam ImageWidthMax = 2304;
localparam ImageHeightMax = 1296+2; // +2 rows for embedded statistics (histogram)
localparam ImageSizeMax = ImageWidthMax*ImageHeightMax;

`endif
