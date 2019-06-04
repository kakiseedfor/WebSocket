//
//  WebSocketFileManager.m
//  WebSocket
//
//  Created by kakiYen on 2019/5/24.
//  Copyright © 2019 kakiYen. All rights reserved.
//

#import "WebSocketFileManager.h"

extern STATUS_CODE Code_Connection;

@interface WebSocketInputStream : NSObject<NSStreamDelegate>
@property (weak, nonatomic) id<WebSoketProtocol> delegate;
@property (strong, atomic) NSMutableArray<NSString *> *filePaths;
@property (strong, nonatomic) NSInputStream *inputStream;
@property (nonatomic) unsigned long long fileSize;
@property (nonatomic) dispatch_queue_t dispatchQueue;
@property (nonatomic) NSInteger readSize;
@property (nonatomic) OPCode opCode;

@end

@implementation WebSocketInputStream

- (void)dealloc{
    NSLog(@"%s",__FUNCTION__);
    
    [self closeStream];
    [NSNotificationCenter.defaultCenter removeObserver:self name:kReachabilityChangedNotification object:nil];
}

- (instancetype)initWith:(id<WebSoketProtocol>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _filePaths = [NSMutableArray array];
        _dispatchQueue = dispatch_queue_create("WebSocket.InputStream", DISPATCH_QUEUE_SERIAL);
        
        dispatch_set_target_queue(_dispatchQueue, ShareTargetQueue());
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(notificationStatusCode:) name:kReachabilityChangedNotification object:nil];
    }
    return self;
}

-(void)readFromFilePath:(NSString *)filePath{
    if ([NSFileManager.defaultManager fileExistsAtPath:filePath]) {
        [self.filePaths addObject:filePath];
        [self startReading];
    }
}

- (void)startReading{
    if (!_inputStream) {
        NSError *error = nil;
        NSString *filePath = _filePaths.firstObject;
        [_filePaths removeObject:filePath];
        
        NSDictionary *dic = [NSFileManager.defaultManager attributesOfItemAtPath:filePath error:&error];
        if (!error) {
            _opCode = BinaryFrame_OPCode;
            _fileSize = [dic[NSFileSize] unsignedLongLongValue];
            _inputStream = [NSInputStream inputStreamWithFileAtPath:filePath];
            _inputStream.delegate = self;
            [self openStream];
        }
    }
}

- (void)sendData:(NSData *)data{
    dispatch_data_t dispatchData = dispatch_data_create(data.bytes, data.length, nil, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    do {
        size_t length = dispatch_data_get_size(dispatchData);
        dispatch_data_t subDispatchData = dispatch_data_create_subrange(dispatchData, 0, length > fragment ? fragment : length);
        
        size_t subLength = dispatch_data_get_size(subDispatchData);
        if (self.isConnected) {
            _fileSize -= subLength;
            NSData *subData = SerializeData((NSData *)subDispatchData, _opCode, _fileSize ? FIN_CONTINUE_MASK : FIN_FINAL_MASK);
            ![_delegate respondsToSelector:@selector(finishSerializeToSend:)] ? : [_delegate finishSerializeToSend:subData];
        }
        
        dispatchData = dispatch_data_create_subrange(dispatchData, subLength, length - subLength);
        
        _opCode = Continue_OPCode;
    } while (dispatch_data_get_size(dispatchData));
}

- (void)readData{
    self.isConnected ? : [self closeStream];    //断开Socket连接情况下，直接关闭流接口[此时应该未有数据被读取]
    
    while (_inputStream.hasBytesAvailable) {
        uint8_t buffer[getpagesize()];
        NSInteger length = [_inputStream read:buffer maxLength:getpagesize()];
        
        if (length) {
            NSData *data = [NSData dataWithBytes:buffer length:length];
            
            dispatch_async(_dispatchQueue, ^{      //防止文本、图片发送的数据流紊乱
                [self sendData:data];
            });
        }
    }
}

- (void)openStream{
    [_inputStream scheduleInRunLoop:Thread.shareInstance.runLoop forMode:NSDefaultRunLoopMode];
    [_inputStream open];
}

- (void)closeStream{
    [_inputStream close];
    [_inputStream removeFromRunLoop:Thread.shareInstance.runLoop forMode:NSDefaultRunLoopMode];
    _inputStream = nil;
}

- (BOOL)isReading{
    return _inputStream ? YES : NO;
}

- (void)notificationStatusCode:(NSNotification *)notification{
    WebSocketReachability *reachability = notification.object;
    switch (reachability.currentReachabilityStatus) {
        case ReachableViaWiFi:
        case ReachableViaWWAN:
            [self openStream];
            break;
        default:
            [self closeStream];
            break;
    }
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode{
    switch (eventCode) {
        case NSStreamEventHasBytesAvailable:
            [self readData];
            break;
        case NSStreamEventEndEncountered:{
            [self closeStream];
            dispatch_async(_dispatchQueue, ^{   //确保前一张图片读取完并发送完毕
                [self startReading];
            });
        }
            break;
        case NSStreamEventErrorOccurred:
            [self closeStream];
            break;
        default:
            break;
    }
}

- (BOOL)isConnected{
    return Code_Connection == Status_Code_Connection_Normal;
}

@end

@interface WebSocketFileManager ()<NSStreamDelegate, WebSoketProtocol>
@property (weak, nonatomic) id<WebSoketProtocol> delegate;
@property (strong, nonatomic) NSString *outputPath;
@property (strong, nonatomic) NSOutputStream *outputStream;
@property (strong, nonatomic) WebSocketInputStream *inputStream;

@end

@implementation WebSocketFileManager

- (void)dealloc
{
    [self closeStream];
    NSLog(@"%s",__FUNCTION__);
}

- (instancetype)initWith:(id<WebSoketProtocol>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _inputStream = [[WebSocketInputStream alloc] initWith:self];
    }
    return self;
}

- (void)writeData:(NSData *)data isFinish:(BOOL)isFinish{
    NSInteger length = [self.outputStream write:data.bytes maxLength:data.length];
    !(length < data.length) ? : [self closeStream];

    if (isFinish) {
        [self closeStream];
        ![_delegate respondsToSelector:@selector(finishDeserializeFile:)] ? : [_delegate finishDeserializeFile:_outputPath];
    }
}

- (void)sendFile:(NSString *)filePath{
    [_inputStream readFromFilePath:filePath];
}

- (void)closeStream{
    [_outputStream close];
    [_outputStream removeFromRunLoop:Thread.shareInstance.runLoop forMode:NSDefaultRunLoopMode];
    
    _outputStream = nil;
    _outputPath = nil;
}

- (NSString *)cacheFilePath{
    NSURL *url = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    
    NSString *filePath = [url.relativePath stringByAppendingString:@"/WebSocket"];
    if (![NSFileManager.defaultManager fileExistsAtPath:filePath]) {
        NSError *error = nil;
        [NSFileManager.defaultManager createDirectoryAtPath:filePath withIntermediateDirectories:YES attributes:nil error:&error];
        !error ? : NSLog(@"%@",error.domain);
    }
    NSLog(@"%@",filePath);
    
    return filePath;
}

- (void)finishSerializeToSend:(NSData *)data{
    ![_delegate respondsToSelector:@selector(finishSerializeToSend:)] ? : [_delegate finishSerializeToSend:data];
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode{
    switch (eventCode) {
        case NSStreamEventErrorOccurred:
            [self closeStream];
            break;
        default:
            break;
    }
}

- (NSOutputStream *)outputStream{
    if (!_outputStream) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"YYYYMMddHHmmssSSS"];
        NSString *fileName = [formatter stringFromDate:NSDate.date];
        
        _outputPath = [self.cacheFilePath stringByAppendingFormat:@"/%@",fileName];
        NSOutputStream *outputStream = [NSOutputStream outputStreamToFileAtPath:_outputPath append:YES];
        outputStream.delegate = self;
        [outputStream scheduleInRunLoop:Thread.shareInstance.runLoop forMode:NSDefaultRunLoopMode];
        [outputStream open];
        
        _outputStream = outputStream;
    }
    
    return _outputStream;
}

@end
