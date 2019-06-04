//
//  WebSocketUtility.h
//  WebSocket
//
//  Created by kakiYen on 2019/5/22.
//  Copyright © 2019 kakiYen. All rights reserved.
//

#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#import "WebSocketHeader.h"

typedef void(^CallBack)(NSData *data);

CFHTTPMessageRef ShakehandHeader(NSString *secWebSocketKey, NSURLRequest *request, NSArray<NSHTTPCookie *> *_Nullable cookies);

NSData *SerializeData(NSData *data, OPCode opCode, FIN_MASK finMask);

dispatch_queue_t ShareTargetQueue(void);

NSCondition *ShareCondition(void);

NSData *SHA1Data(NSString *input);

NSString *OriginUrl(NSURL *url);

void SendData(NSData *data, OPCode opCode, CallBack callBack);

void MaskByteWith(uint8_t *byte, uint8_t *mask, size_t length);


/*
 公共接口
 */

@protocol WebSoketProtocol <NSObject>

@optional
- (void)finishDeserializeString:(NSString *)text opCode:(OPCode)opCode;

- (void)saveData:(NSData *)data isFinish:(BOOL)isFinish;

- (void)finishDeserializeFile:(NSString *)filePath;

- (void)finishDeserializeError:(NSError *)error;

- (void)finishSerializeToSend:(NSData *)data;

@end

@protocol WebSocketDelegate <NSObject>

- (void)didCloseWebSocket;

- (void)didConnectWebSocket;

- (void)didReceiveText:(NSString *)text;

- (void)didReceiveFile:(NSString *)filePath;

- (void)connectionWithError:(NSError *)error;

@end

@interface Thread : NSThread

+ (Thread *)shareInstance;

- (NSRunLoop *)runLoop;

@end
