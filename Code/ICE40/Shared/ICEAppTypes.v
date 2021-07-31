`ifndef ICEAppTypes_v
`define ICEAppTypes_v

`define Msg_Len                                                 64

`define Msg_Type_Len                                            8
`define Msg_Type_Bits                                           63:56

`define Msg_Arg_Len                                             56
`define Msg_Arg_Bits                                            55:0

`define Resp_Len                                                `Msg_Len
`define Resp_Arg_Bits                                           63:0

`define Msg_Type_Echo                                           `Msg_Type_Len'h00
`define     Msg_Arg_Echo_Msg_Len                                56
`define     Msg_Arg_Echo_Msg_Bits                               55:0
`define     Resp_Arg_Echo_Msg_Bits                              63:8

`define Msg_Type_LEDSet                                         `Msg_Type_Len'h01
`define     Msg_Arg_LEDSet_Val_Len                              4
`define     Msg_Arg_LEDSet_Val_Bits                             3:0

`define Msg_Type_SDInit                                         `Msg_Type_Len'h02
`define     Msg_Arg_SDInit_ClkSrc_Delay_Len                     4
`define     Msg_Arg_SDInit_ClkSrc_Delay_Bits                    7:4
`define     Msg_Arg_SDInit_ClkSrc_Speed_Len                     2
`define     Msg_Arg_SDInit_ClkSrc_Speed_Bits                    3:2
`define     Msg_Arg_SDInit_ClkSrc_Speed_Off                     `Msg_Arg_SDInit_ClkSrc_Speed_Len'b00
`define     Msg_Arg_SDInit_ClkSrc_Speed_Slow                    `Msg_Arg_SDInit_ClkSrc_Speed_Len'b01
`define     Msg_Arg_SDInit_ClkSrc_Speed_Fast                    `Msg_Arg_SDInit_ClkSrc_Speed_Len'b10
`define     Msg_Arg_SDInit_Trigger_Len                          1
`define     Msg_Arg_SDInit_Trigger_Bits                         1:1
`define     Msg_Arg_SDInit_Rst_Len                              1
`define     Msg_Arg_SDInit_Rst_Bits                             0:0

`define Msg_Type_SDSendCmd                                      `Msg_Type_Len'h03
`define     Msg_Arg_SDSendCmd_RespType_Len                      2
`define     Msg_Arg_SDSendCmd_RespType_Bits                     50:49
`define     Msg_Arg_SDSendCmd_RespType_136                      `Msg_Arg_SDSendCmd_RespType_Len'b10
`define     Msg_Arg_SDSendCmd_RespType_136_Bits                 50:50
`define     Msg_Arg_SDSendCmd_RespType_48                       `Msg_Arg_SDSendCmd_RespType_Len'b01
`define     Msg_Arg_SDSendCmd_RespType_48_Bits                  49:49
`define     Msg_Arg_SDSendCmd_RespType_None                     `Msg_Arg_SDSendCmd_RespType_Len'b00
`define     Msg_Arg_SDSendCmd_DatInType_Len                     1
`define     Msg_Arg_SDSendCmd_DatInType_Bits                    48:48
`define     Msg_Arg_SDSendCmd_DatInType_512                     `Msg_Arg_SDSendCmd_DatInType_Len'b1
`define     Msg_Arg_SDSendCmd_DatInType_512_Bits                48:48
`define     Msg_Arg_SDSendCmd_DatInType_None                    `Msg_Arg_SDSendCmd_DatInType_Len'b0
`define     Msg_Arg_SDSendCmd_CmdData_Bits                      47:0

`define Msg_Type_SDGetStatus                                    `Msg_Type_Len'h04
`define     Resp_Arg_SDGetStatus_InitDone_Bits                  63:63
`define     Resp_Arg_SDGetStatus_CmdDone_Bits                   62:62
`define     Resp_Arg_SDGetStatus_RespDone_Bits                  61:61
`define         Resp_Arg_SDGetStatus_RespCRCErr_Bits            60:60
`define         Resp_Arg_SDGetStatus_Resp_Bits                  59:12
`define         Resp_Arg_SDGetStatus_Resp_Len                   48
`define     Resp_Arg_SDGetStatus_DatOutDone_Bits                11:11
`define         Resp_Arg_SDGetStatus_DatOutCRCErr_Bits          10:10
`define     Resp_Arg_SDGetStatus_DatInDone_Bits                 9:9
`define         Resp_Arg_SDGetStatus_DatInCRCErr_Bits           8:8
`define         Resp_Arg_SDGetStatus_DatInCMD6AccessMode_Bits   7:4
`define     Resp_Arg_SDGetStatus_Dat0Idle_Bits                  3:3

`define Msg_Type_ImgReset                                       `Msg_Type_Len'h05
`define     Msg_Arg_ImgReset_Val_Bits                           0:0

`define Msg_Type_ImgCapture                                     `Msg_Type_Len'h06
`define     Msg_Arg_ImgCapture_DstBlock_Bits                    2:0 // Wider than currently necessary to future-proof

`define Msg_Type_ImgReadout                                     `Msg_Type_Len'h07
`define     Msg_Arg_ImgReadout_Counter_Len                      16
`define     Msg_Arg_ImgReadout_Counter_Bits                     31:16
`define     Msg_Arg_ImgReadout_CaptureNext_Bits                 3:3
`define     Msg_Arg_ImgReadout_SrcBlock_Bits                    2:0 // Wider than currently necessary to future-proof

`define Msg_Type_ImgI2CTransaction                              `Msg_Type_Len'h08
`define     Msg_Arg_ImgI2CTransaction_Write_Bits                55:55
`define     Msg_Arg_ImgI2CTransaction_DataLen_Bits              54:54
`define         Msg_Arg_ImgI2CTransaction_DataLen_1             1'b0
`define         Msg_Arg_ImgI2CTransaction_DataLen_2             1'b1
`define     Msg_Arg_ImgI2CTransaction_RegAddr_Bits              31:16
`define     Msg_Arg_ImgI2CTransaction_WriteData_Bits            15:0

`define Msg_Type_ImgI2CStatus                                   `Msg_Type_Len'h09
`define     Resp_Arg_ImgI2CStatus_Done_Bits                     63:63
`define     Resp_Arg_ImgI2CStatus_Err_Bits                      62:62
`define     Resp_Arg_ImgI2CStatus_ReadData_Bits                 61:46

`define Msg_Type_ImgCaptureStatus                               `Msg_Type_Len'h0A
`define     Resp_Arg_ImgCaptureStatus_Done_Bits                 63:63
`define     Resp_Arg_ImgCaptureStatus_ImageWidth_Bits           62:51
`define     Resp_Arg_ImgCaptureStatus_ImageHeight_Bits          50:39
`define     Resp_Arg_ImgCaptureStatus_HighlightCount_Bits       38:21
`define     Resp_Arg_ImgCaptureStatus_ShadowCount_Bits          20:3

`define Msg_Type_NoOp                                           `Msg_Type_Len'hFF

localparam ImageWidthMax = 2304;
localparam ImageHeightMax = 1296+2; // +2 rows for embedded statistics (histogram)

`endif
