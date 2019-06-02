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

@end

@implementation WebSocketInputStream

- (void)dealloc{
    NSLog(@"%s",__FUNCTION__);
    
    [NSNotificationCenter.defaultCenter removeObserver:self name:WebSocket_Notification_Status_Code_Change object:nil];
}

- (instancetype)initWith:(id<WebSoketProtocol>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _filePaths = [NSMutableArray array];
        _dispatchQueue = dispatch_queue_create("WebSocket.InputStream", DISPATCH_QUEUE_SERIAL);
        
        dispatch_set_target_queue(_dispatchQueue, ShareTargetQueue());
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(notificationStatusCode:) name:WebSocket_Notification_Status_Code_Change object:nil];
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
        NSDictionary *dic = [NSFileManager.defaultManager attributesOfItemAtPath:filePath error:&error];
        
        if (!error) {
            _fileSize = [dic[NSFileSize] unsignedLongLongValue];
            _inputStream = [NSInputStream inputStreamWithFileAtPath:filePath];
            _inputStream.delegate = self;
            [self openStream];
            [_filePaths removeObject:filePath];
        }
    }
}

- (void)sendData:(NSData *)data{
    OPCode opCode = BinaryFrame_OPCode;
    dispatch_data_t dispatchData = dispatch_data_create(data.bytes, data.length, nil, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    do {
        size_t length = dispatch_data_get_size(dispatchData);
        dispatch_data_t subDispatchData = dispatch_data_create_subrange(dispatchData, 0, length > fragment ? fragment : length);
        
        dispatchData = dispatch_data_create_subrange(dispatchData, dispatch_data_get_size(subDispatchData), length - dispatch_data_get_size(subDispatchData));
        
        if (self.isConnected) {
            NSData *subData = SerializeData((NSData *)subDispatchData, opCode, _fileSize ? FIN_CONTINUE_MASK : FIN_FINAL_MASK);
            ![_delegate respondsToSelector:@selector(finishSerializeToSend:)] ? : [_delegate finishSerializeToSend:subData];
        }
        opCode = Continue_OPCode;
    } while (dispatchData != dispatch_data_empty);
}

- (void)readData{
    if (self.isConnected) {
        while (_inputStream.hasBytesAvailable) {
            uint8_t buffer[getpagesize()];
            NSInteger length = [_inputStream read:buffer maxLength:getpagesize()];
            
            if (length) {
                NSData *data = [NSData dataWithBytes:buffer length:length];
                
                dispatch_async(_dispatchQueue, ^{      //防止文本、图片发送的数据流紊乱
                    self.fileSize -= length;
                    [self sendData:data];
                });
            }
        }
    }else{  //网络连接不正常
        [self closeStream];
    }
}

- (void)openStream{
    [_inputStream scheduleInRunLoop:Thread.shareInstance.runLoop forMode:NSDefaultRunLoopMode];
    [_inputStream open];
}

- (void)closeStream{
    [_inputStream close];
    [_inputStream removeFromRunLoop:Thread.shareInstance.runLoop forMode:NSDefaultRunLoopMode];
}

- (void)destroyStream{
    [self closeStream];
    _inputStream = nil;
}

- (BOOL)isReading{
    return _inputStream ? YES : NO;
}

- (void)notificationStatusCode:(NSNotification *)notification{
    if (self.isConnected) {
        [self openStream];
    }
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode{
    switch (eventCode) {
        case NSStreamEventHasBytesAvailable:
            [self readData];
            break;
        case NSStreamEventEndEncountered:{
            [self destroyStream];
            dispatch_async(_dispatchQueue, ^{
                [self startReading];
            });
        }
            break;
        case NSStreamEventErrorOccurred:
            [self destroyStream];
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
    [self.outputStream close];
    [self.outputStream removeFromRunLoop:Thread.shareInstance.runLoop forMode:NSDefaultRunLoopMode];
    
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
