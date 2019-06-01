//
//  WebSocketHeader.h
//  WebSocket
//
//  Created by kakiYen on 2019/5/21.
//  Copyright © 2019 kakiYen. All rights reserved.
//

#ifndef WebSocketHeader_h
#define WebSocketHeader_h

#define MASKKEY_MASK 0x80
#define UnMASKKEY_MASK 0x00

typedef NS_ENUM(uint8_t, FIN_MASK) {
    FIN_CONTINUE_MASK = 0x00,
    FIN_FINAL_MASK = 0x80
};

typedef NS_ENUM(uint8_t, PAY_LOAD) {
    PAY_LOAD_126 = 0x7E,
    PAY_LOAD_127 = 0x7F
};

typedef NS_ENUM(uint8_t, RSV_MASK) {
    RSV_ONE_MASK = 0x40,
    RSV_TWO_MASK = 0x20,
    RSV_THREE_MASK = 0x10
};

typedef NS_ENUM(uint8_t, OPCode) {
    Continue_OPCode = 0x00,
    TextFrame_OPCode = 0x01,
    BinaryFrame_OPCode = 0x02,
    Close_OPCode = 0x08,
    Ping_OPCode = 0x09,
    Pong_OPCode = 0x0A,
    None_OPCode = 0x0F,
};

typedef NS_ENUM(NSInteger, STATUS_CODE) {
    Status_Code_Connection_Normal = 1000,
    Status_Code_Connection_Close = 1001,
    Status_Code_Connection_Doing = 1002,
    Status_Code_Connection_Error = 1003,
    Status_Code_Protocol_Error = 1004,
    Status_Code_Invalid_UTF8 = 1007,
};

static size_t fragment = 0x4000;    //分片阀值
static NSString *WebSocket_Notification_Status_Code_Change = @"WebSocket_Notification_Status_Code_Change";

#endif /* WebSocketHeader_h */
