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

`define Msg_Type_SDClkSrc                                       `Msg_Type_Len'h01
`define     Msg_Arg_SDClkSrc_Delay_Bits                         5:2
`define     Msg_Arg_SDClkSrc_Speed_Len                          2
`define     Msg_Arg_SDClkSrc_Speed_Bits                         1:0
`define     Msg_Arg_SDClkSrc_Speed_Off                          `Msg_Arg_SDClkSrc_Speed_Len'b00
`define     Msg_Arg_SDClkSrc_Speed_Slow                         `Msg_Arg_SDClkSrc_Speed_Len'b01
`define     Msg_Arg_SDClkSrc_Speed_Fast                         `Msg_Arg_SDClkSrc_Speed_Len'b10

`define Msg_Type_SDSendCmd                                      `Msg_Type_Len'h02
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

`define Msg_Type_SDGetStatus                                    `Msg_Type_Len'h03
`define     Resp_Arg_SDGetStatus_CmdDone_Bits                   63:63
`define     Resp_Arg_SDGetStatus_RespDone_Bits                  62:62
`define         Resp_Arg_SDGetStatus_RespCRCErr_Bits            61:61
`define         Resp_Arg_SDGetStatus_Resp_Bits                  60:13
`define         Resp_Arg_SDGetStatus_Resp_Len                   48
`define     Resp_Arg_SDGetStatus_DatOutDone_Bits                12:12
`define         Resp_Arg_SDGetStatus_DatOutCRCErr_Bits          11:11
`define     Resp_Arg_SDGetStatus_DatInDone_Bits                 10:10
`define         Resp_Arg_SDGetStatus_DatInCRCErr_Bits           9:9
`define         Resp_Arg_SDGetStatus_DatInCMD6AccessMode_Bits   8:5
`define     Resp_Arg_SDGetStatus_Dat0Idle_Bits                  4:4

`define Msg_Type_PixReset                                       `Msg_Type_Len'h04
`define     Msg_Arg_PixReset_Val_Bits                           0:0

`define Msg_Type_PixCapture                                     `Msg_Type_Len'h05
`define     Msg_Arg_PixCapture_DstBlock_Bits                    2:0

`define Msg_Type_PixReadout                                     `Msg_Type_Len'h06
`define     Msg_Arg_PixReadout_Counter_Len                      16
`define     Msg_Arg_PixReadout_Counter_Bits                     31:16
`define     Msg_Arg_PixReadout_CaptureNext_Bits                 3:3
`define     Msg_Arg_PixReadout_SrcBlock_Bits                    2:0

`define Msg_Type_PixI2CTransaction                              `Msg_Type_Len'h07
`define     Msg_Arg_PixI2CTransaction_Write_Bits                55:55
`define     Msg_Arg_PixI2CTransaction_DataLen_Bits              54:54
`define         Msg_Arg_PixI2CTransaction_DataLen_1             1'b0
`define         Msg_Arg_PixI2CTransaction_DataLen_2             1'b1
`define     Msg_Arg_PixI2CTransaction_RegAddr_Bits              31:16
`define     Msg_Arg_PixI2CTransaction_WriteData_Bits            15:0

`define Msg_Type_PixGetStatus                                   `Msg_Type_Len'h08
`define     Resp_Arg_PixGetStatus_I2CDone_Bits                  63:63
`define     Resp_Arg_PixGetStatus_I2CErr_Bits                   62:62
`define     Resp_Arg_PixGetStatus_I2CReadData_Bits              61:46
`define     Resp_Arg_PixGetStatus_CaptureDone_Bits              45:45
`define     Resp_Arg_PixGetStatus_CaptureImageWidth_Bits        44:33
`define     Resp_Arg_PixGetStatus_CaptureImageHeight_Bits       32:21

`define Msg_Type_NoOp                                           `Msg_Type_Len'hFF

localparam ImageWidthMax = 2304;
localparam ImageHeightMax = 1296+2; // +2 rows for embedded statistics (histogram)

`endif