//
//  WebSocketUtility.m
//  WebSocket
//
//  Created by kakiYen on 2019/5/22.
//  Copyright © 2019 kakiYen. All rights reserved.
//

#import "WebSocketUtility.h"

STATUS_CODE Code_Connection = Status_Code_Connection_Close;

void MaskByteWith(uint8_t *byte, uint8_t *mask, size_t length){
    for (size_t i = 0; i < length; i++) {
        byte[i] = byte[i] ^ mask[i % sizeof(uint32_t)];
    }
}

NSData *SHA1Data(NSString *input){
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    
    unsigned char output[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, output);
    
    return [NSData dataWithBytes:output length:CC_SHA1_DIGEST_LENGTH];
}

dispatch_queue_t ShareTargetQueue(){
    static dispatch_once_t dispatchOnce;
    
    static dispatch_queue_t targetQueue;
    dispatch_once(&dispatchOnce, ^{
        targetQueue = dispatch_queue_create("WebSoket.Serialization.Target", DISPATCH_QUEUE_SERIAL);
    });
    return targetQueue;
}

NSCondition *ShareCondition(){
    static dispatch_once_t dispatchOnce;
    
    static NSCondition *condition = nil;
    dispatch_once(&dispatchOnce, ^{
        condition = [[NSCondition alloc] init];
    });
    return condition;
}

void SendData(NSData *data, OPCode opCode, CallBack callBack){
    dispatch_queue_t queue = dispatch_queue_create("WebSoket.Serialization.Target", DISPATCH_QUEUE_SERIAL); //确保每次的数据发送完后再发下一个
    
    opCode != TextFrame_OPCode ? : dispatch_set_target_queue(queue, ShareTargetQueue());
    
    dispatch_data_t dispatchData = dispatch_data_create(data.bytes, data.length, nil, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    do {
        size_t length = dispatch_data_get_size(dispatchData);
        dispatch_data_t subDispatchData = dispatch_data_create_subrange(dispatchData, 0, length > fragment ? fragment : length);
        
        dispatchData = dispatch_data_create_subrange(dispatchData, dispatch_data_get_size(subDispatchData), length - dispatch_data_get_size(subDispatchData));
        dispatch_async(queue, ^{
            if (Code_Connection == Status_Code_Connection_Normal) {
                NSData *subData = SerializeData((NSData *)subDispatchData, opCode, dispatchData == dispatch_data_empty ? FIN_FINAL_MASK : FIN_CONTINUE_MASK);
                !callBack ? : callBack(subData);
            }
        });
        opCode = Continue_OPCode;
    } while (dispatchData != dispatch_data_empty);
}

NSData *SerializeData(NSData *data, OPCode opCode, FIN_MASK finMask){
    const void *bytes = data.bytes;
    dispatch_data_t dispatchData = dispatch_data_create(data.bytes, data.length, nil, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    
    dispatch_data_t bufferData = dispatch_data_create_concat(dispatchData, dispatch_data_empty);
    size_t payload = dispatch_data_get_size(bufferData);
    
    uint64_t extendPayload = 0;
    size_t frameByteLength = sizeof(uint16_t);
    size_t maskByteLength = (opCode == Close_OPCode ? 0 : sizeof(uint32_t));
    size_t extendLength = 0;
    size_t tempPayload = payload;
    if (tempPayload < PAY_LOAD_126) {
        
    }else{
        if (tempPayload < UINT16_MAX) {
            extendPayload = CFSwapInt16BigToHost(tempPayload);
            extendLength += sizeof(uint16_t);
            payload = PAY_LOAD_126;
        }else{
            extendPayload = CFSwapInt64BigToHost(tempPayload);
            extendLength += sizeof(uint64_t);
            payload = PAY_LOAD_127;
        }
    }
    
    NSMutableData *frameData = [[NSMutableData alloc] initWithLength:frameByteLength + extendLength + maskByteLength + tempPayload];
    uint8_t *frameBuffer = (uint8_t *)frameData.bytes;
    
    frameBuffer[0] |= finMask;
    frameBuffer[0] |= opCode;
    frameBuffer[1] |= (opCode == Close_OPCode ? UnMASKKEY_MASK : MASKKEY_MASK);
    frameBuffer[1] |= payload;
    
    frameBuffer += frameByteLength;
    if (extendLength) {
        memcpy(frameBuffer, &extendPayload, extendLength);
        frameBuffer += extendLength;
    }
    
    uint8_t *mask = frameBuffer;
    assert(SecRandomCopyBytes(kSecRandomDefault, maskByteLength, mask) == 0);
    frameBuffer += maskByteLength;
    
    memcpy(frameBuffer, bytes, tempPayload);
    !maskByteLength ? : MaskByteWith(frameBuffer, mask, tempPayload);
    
    return frameData;
}

NSString *OriginUrl(NSURL *url){
    NSString *scheme = url.scheme.lowercaseString;
    scheme = [scheme isEqualToString:@"wss"] ? @"https" : ([scheme isEqualToString:@"ws"] ? @"http" : @"ws");
    
    NSString *port = url.port.stringValue;
    port = port.length ? port : ([scheme isEqualToString:@"https"] ? @"443" : @"80");
    
    NSString *relativePath = url.relativePath;
    NSString *query = url.query;
    NSMutableString *urlString = [NSMutableString stringWithFormat:@"%@://%@:%@",scheme, url.host, port];
    !relativePath.length ? : [urlString appendFormat:@"%@",relativePath];
    !query.length ? : [urlString appendFormat:@"?%@",query];
    return urlString;
}

/**
 Http 1.x无状态协议：
    1、每个请求都是相互独立的[即当前请求是不知道上个请求是失败或成功]
    2、每个请求都包含了完整的请求所需的信息[造成每次请求，Http协议头都可能会携带相同的信息]，
    3、发送请求不涉及状态变更[即只有成功或失败]
 */
CFHTTPMessageRef ShakehandHeader(NSString *secWebSocketKey, NSURLRequest *request, NSArray<NSHTTPCookie *> *_Nullable cookies){
    CFHTTPMessageRef messageRef = CFHTTPMessageCreateRequest(kCFAllocatorDefault, CFSTR("GET"), (__bridge CFURLRef _Nonnull)request.URL, kCFHTTPVersion1_1);
    CFHTTPMessageSetHeaderFieldValue(messageRef, CFSTR("Host"), (__bridge CFStringRef _Nullable)(request.URL.host));
    CFHTTPMessageSetHeaderFieldValue(messageRef, CFSTR("Upgrade"), CFSTR("websocket"));
    CFHTTPMessageSetHeaderFieldValue(messageRef, CFSTR("Connection"), CFSTR("Upgrade"));
    CFHTTPMessageSetHeaderFieldValue(messageRef, CFSTR("Sec-WebSocket-Key"), (__bridge CFStringRef _Nullable)secWebSocketKey);
    CFHTTPMessageSetHeaderFieldValue(messageRef, CFSTR("Origin"), (__bridge CFStringRef _Nullable)OriginUrl(request.URL));
    CFHTTPMessageSetHeaderFieldValue(messageRef, CFSTR("Sec-WebSocket-Version"), CFSTR("13"));
    CFHTTPMessageSetHeaderFieldValue(messageRef, CFSTR("Sec-WebSocket-Protocol"), CFSTR(""));
    CFHTTPMessageSetHeaderFieldValue(messageRef, CFSTR("Sec-WebSocket-Extensions"), CFSTR(""));
    
    [cookies enumerateObjectsUsingBlock:^(NSHTTPCookie * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        CFHTTPMessageSetHeaderFieldValue(messageRef, (__bridge CFStringRef _Nonnull)obj.name, (__bridge CFStringRef _Nonnull)obj.value);
    }];
    
    [request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
        CFHTTPMessageSetHeaderFieldValue(messageRef, (__bridge CFStringRef _Nonnull)key, (__bridge CFStringRef _Nonnull)obj);
    }];
    
    return messageRef;
}

@interface Thread ()
@property (weak, nonatomic) NSRunLoop *runLoop;
@property (nonatomic) dispatch_semaphore_t semaphore;

@end

@implementation Thread

- (void)dealloc{
    NSLog(@"%s",__FUNCTION__);
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.name = @"WebSocket.Thread";
        _semaphore = dispatch_semaphore_create(0);
    }
    return self;
}

+ (Thread *)shareInstance{
    static dispatch_once_t dispatchOnce;
    
    static Thread *thread = nil;
    dispatch_once(&dispatchOnce, ^{
        thread = [[Thread alloc] init];
        [thread start];
    });
    
    return thread;
}

- (void)main{
    @autoreleasepool{
        _runLoop = NSRunLoop.currentRunLoop;
        dispatch_semaphore_signal(_semaphore);
        
        CFRunLoopSourceContext context = {
            .version = 0,
            .info = NULL,
            .retain = NULL,
            .release = NULL,
            .copyDescription = NULL,
            .equal = NULL,
            .schedule = NULL,
            .cancel = NULL,
            .perform = NULL,
        };
        CFRunLoopSourceRef sourceRef = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context);
        CFRunLoopAddSource(_runLoop.getCFRunLoop, sourceRef, kCFRunLoopDefaultMode);
        CFRelease(sourceRef);
        
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, NSDate.distantFuture.timeIntervalSinceReferenceDate, false);
        NSLog(@"The Thread was stopped!");
    }
}

- (NSRunLoop *)runLoop{
    if (!_runLoop) {
        dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    }
    return _runLoop;
}

@end
