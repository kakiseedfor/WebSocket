//
//  WebSocketProxy.m
//  WebSocket
//
//  Created by kakiYen on 2019/5/29.
//  Copyright © 2019 kakiYen. All rights reserved.
//

#import "WebSocketProxy.h"
#import "WebSocketUtility.h"
#import <CoreTelephony/CTCellularData.h>

extern STATUS_CODE Code_Connection;

@interface WebSocketProxy ()<NSStreamDelegate>
@property (weak, nonatomic) id<WebSocketProxyDelegate> delegate;
@property (strong, nonatomic) NSOutputStream *outputStream;
@property (strong, nonatomic) NSInputStream *inputStream;
@property (strong, nonatomic) NSMutableData *headerData;
@property (strong, nonatomic) NSURLRequest *request;
@property (strong, nonatomic) NSString *securityKey;
@property (strong, nonatomic) NSURL *url;

@property (nonatomic) dispatch_block_t timer;
@property (nonatomic) BOOL sendHeader;
@property (nonatomic) BOOL trust;

@end

@implementation WebSocketProxy

- (instancetype)initWith:(id<WebSocketProxyDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        
    }
    return self;
}

- (void)connect:(NSString *)urlString{
    _url = [NSURL URLWithString:urlString];
    _request = [NSURLRequest requestWithURL:_url];
    
    CTCellularData *cellularData = [[CTCellularData alloc] init];
    cellularData.cellularDataRestrictionDidUpdateNotifier = ^(CTCellularDataRestrictedState state) {
        switch (state) {
            case kCTCellularDataRestrictedStateUnknown:
                NSLog(@"kCTCellularDataRestrictedStateUnknown");
                break;
            case kCTCellularDataNotRestricted:
                [self startConnect];
                break;
            case kCTCellularDataRestricted:
                NSLog(@"kCTCellularDataRestricted");
                break;
            default:
                break;
        }
    };
}

- (void)reconnect{
    [self startConnect];
}

- (void)startConnect{
    _headerData = [NSMutableData data];
    
    NSURL *tempUrl = [NSURL URLWithString:[NSString stringWithFormat:self.isSecurity ? @"https://%@" : @"http://%@",_url.host]];
    
    CFDictionaryRef dicRef = CFNetworkCopySystemProxySettings();
    CFArrayRef arrayRef = CFNetworkCopyProxiesForURL((__bridge CFURLRef _Nonnull)(tempUrl), dicRef);
    
    if (CFArrayGetCount(arrayRef)) {
        CFDictionaryRef dic = CFArrayGetValueAtIndex(arrayRef, 0);
        CFStringRef proxyType =  CFDictionaryGetValue(dic, kCFProxyTypeKey);
        NSLog(@"%@",proxyType);
    }
    
    [self initialStream];
    [self countdown];   //连接超时处理
}

- (void)countdown{
    _timer = dispatch_block_create(DISPATCH_BLOCK_DETACHED, ^{
        if (Code_Connection != Status_Code_Connection_Normal) {
            [self closeStream];
            
            NSError *error = [NSError errorWithDomain:@"The connection is timeout!" code:Status_Code_Connection_Error userInfo:@{}];
            ![self.delegate respondsToSelector:@selector(didConnect:outputStream:error:)] ? : [self.delegate didConnect:self.inputStream outputStream:self.outputStream error:error];
        }
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, timeout * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), _timer);
}

- (void)initialStream{
    UInt32 port = _url.port.unsignedIntValue ? _url.port.unsignedIntValue : (self.isSecurity ? 443 : 80);
    
    CFReadStreamRef readStreamRef;
    CFWriteStreamRef writeStreamRef;
    CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, (__bridge CFStringRef)_url.host, port, &readStreamRef, &writeStreamRef);
    
    if (self.isSecurity) {
        CFMutableDictionaryRef settings = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, NULL);
        CFDictionarySetValue(settings, kCFStreamSSLLevel, kCFStreamSocketSecurityLevelTLSv1);   //设置SSL/TLS版本号
        CFDictionarySetValue(settings, kCFStreamSSLPeerName, kCFNull);  //设置校验域名
        CFReadStreamSetProperty(readStreamRef, kCFStreamPropertySSLSettings, settings);
        CFWriteStreamSetProperty(writeStreamRef, kCFStreamPropertySSLSettings, settings);
    }
    
    _inputStream = (__bridge NSInputStream *)readStreamRef;
    _outputStream = (__bridge NSOutputStream *)writeStreamRef;
    _inputStream.delegate = self;
    _outputStream.delegate = self;
    
    [_inputStream scheduleInRunLoop:Thread.shareInstance.runLoop forMode:NSDefaultRunLoopMode];
    [_outputStream scheduleInRunLoop:Thread.shareInstance.runLoop forMode:NSDefaultRunLoopMode];
    [_inputStream open];
    [_outputStream open];
}

- (void)closeStream{
    [_inputStream close];
    [_outputStream close];
    [_inputStream removeFromRunLoop:Thread.shareInstance.runLoop forMode:NSDefaultRunLoopMode];
    [_outputStream removeFromRunLoop:Thread.shareInstance.runLoop forMode:NSDefaultRunLoopMode];
    [self resetStream];
}

- (void)resetStream{
    dispatch_block_cancel(_timer);
    
    _timer = nil;
    _trust = NO;
    _sendHeader = NO;
    _headerData = nil;
    _securityKey = nil;
    _inputStream = nil;
    _outputStream = nil;
}

- (void)sendShakehandHeader{
    if (!_sendHeader) {
        _sendHeader = YES;
        
        uint8_t bytes[16];
        NSAssert(SecRandomCopyBytes(kSecRandomDefault, 16, bytes) == 0, @"Failed to generate random bytes");
        _securityKey = [[NSData dataWithBytes:bytes length:16] base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
        
        CFHTTPMessageRef messageRef = ShakehandHeader(_securityKey, _request, @[]);
        NSData *data = (__bridge NSData *)CFHTTPMessageCopySerializedMessage(messageRef);
        
        NSInteger length = [self.outputStream write:data.bytes maxLength:data.length];
        if (length < data.length) {
            [self closeStream];
            NSError *error = [NSError errorWithDomain:@"Occur error when sending ShakehandHeader" code:Status_Code_Connection_Error userInfo:@{}];
            ![self.delegate respondsToSelector:@selector(didConnect:outputStream:error:)] ? : [self.delegate didConnect:self.inputStream outputStream:self.outputStream error:error];
        }
    }
}

- (void)receiveShakehandHeader{
    uint8_t buffer[getpagesize()];
    NSInteger length = [_inputStream read:buffer maxLength:getpagesize()];
    
    [_headerData appendData:[NSData dataWithBytes:buffer length:length]];
    NSRange range = [_headerData rangeOfData:self.seperateData options:NSDataSearchBackwards | NSDataSearchAnchored range:NSMakeRange(0, _headerData.length)];
    if (_headerData && range.location != NSNotFound) {
        NSData * data = [_headerData subdataWithRange:NSMakeRange(0, range.location + range.length)];
        CFHTTPMessageRef messageRef = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, false);
        CFHTTPMessageAppendBytes(messageRef, data.bytes, data.length);
        
        CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(messageRef);
        NSError *error = statusCode < 400 ? nil : [NSError errorWithDomain:[NSString stringWithFormat:@"Request failed with response code %ld",(long)statusCode] code:Status_Code_Connection_Error userInfo:@{}];
        
        if (!error) {
            NSString *accept = (__bridge NSString *)(CFHTTPMessageCopyHeaderFieldValue(messageRef, CFSTR("Sec-WebSocket-Accept")));
            
            NSMutableString *securityKey = [NSMutableString stringWithString:_securityKey];
            [securityKey appendString:self.appendSecurityKey];
            
            NSString *SHA1 = [SHA1Data(securityKey) base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
            if (![accept isEqualToString:SHA1]) {
                error = [NSError errorWithDomain:@"Verify Sec-WebSocket-Key failed!" code:Status_Code_Connection_Error userInfo:@{}];
            }
            
            NSString *protocol = (__bridge NSString *)(CFHTTPMessageCopyHeaderFieldValue(messageRef, CFSTR("Sec-WebSocket-Protocol")));
            if (!error && protocol.length) {
                error = [NSError errorWithDomain:@"The Sec-WebSocket-Protocol has not setted!" code:Status_Code_Connection_Error userInfo:@{}];
            }
        }
        
        ![self.delegate respondsToSelector:@selector(didConnect:outputStream:error:)] ? : [self.delegate didConnect:self.inputStream outputStream:self.outputStream error:error];
        error ? [self closeStream] : [self resetStream];
         NSLog(@"%@",[[NSString alloc] initWithData:(__bridge NSData * _Nonnull)(CFHTTPMessageCopySerializedMessage(messageRef)) encoding:NSUTF8StringEncoding]);
    }
}

- (BOOL)checkSecurity:(NSStream *)aStream{
    SecTrustRef trustRef;
    SecTrustResultType resultType;
    SecPolicyRef policyRef = SecPolicyCreateSSL(NO, (__bridge CFStringRef _Nullable)_url.host);
    CFArrayRef arrayRef = (__bridge CFArrayRef)[aStream propertyForKey:(NSString *)kCFStreamPropertySSLPeerCertificates];
    SecTrustCreateWithCertificates(arrayRef, policyRef, &trustRef);
    OSStatus status = SecTrustEvaluate(trustRef, &resultType);
    
    _trust = status == errSecSuccess && (resultType == kSecTrustResultUnspecified || resultType == kSecTrustResultProceed) ? YES : NO;
    return _trust;
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode{
    switch (eventCode) {
        case NSStreamEventHasBytesAvailable:
            _trust = self.isSecurity ? (_trust ? _trust : [self checkSecurity:aStream]) : YES;
            _trust ? [self receiveShakehandHeader] : [self closeStream];
            break;
        case NSStreamEventHasSpaceAvailable:
            _trust = self.isSecurity ? (_trust ? _trust : [self checkSecurity:aStream]) : YES;
            _trust ? [self sendShakehandHeader] : [self closeStream];
            break;
        case NSStreamEventErrorOccurred:{
            NSError *error = [NSError errorWithDomain:@"Connection occur error!" code:Status_Code_Connection_Error userInfo:@{}];
            ![self.delegate respondsToSelector:@selector(didConnect:outputStream:error:)] ? : [self.delegate didConnect:self.inputStream outputStream:self.outputStream error:error];
            [self closeStream];
        }
            break;
        default:
            break;
    }
}

- (NSString *)appendSecurityKey{
    return @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
}

- (NSData *)seperateData{
    return [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)isSecurity{
    return [_url.scheme.lowercaseString isEqualToString:@"wss"];
}

@end
