//
//  WebSocketManager.m
//  WebSocket
//
//  Created by kakiYen on 2019/5/21.
//  Copyright © 2019 kakiYen. All rights reserved.
//

#import "WebSocketProxy.h"
#import "WebSocketManager.h"

extern STATUS_CODE Code_Connection;

@interface WebSocketManager ()<WebSoketProtocol, WebSocketProxyDelegate, NSStreamDelegate>
@property (weak, nonatomic) id<WebSocketDelegate> delegate;
@property (strong, nonatomic) WebSocketDeserialization *deserialization;
@property (strong, nonatomic) WebSocketFileManager *fileManager;
@property (strong, nonatomic) WebSocketProxy *socketProxy;
@property (strong, nonatomic) NSOutputStream *outputStream;
@property (strong, nonatomic) NSInputStream *inputStream;
@property (nonatomic) dispatch_queue_t writeQueue;  //考虑到弱网、无网情况及实时发送特殊的OPCode；确保每个线程对writeDispatchData是安全的
@property (nonatomic) dispatch_queue_t readQueue;  //考虑到弱网情况，需要形成生产消费者模式；确保每个线程对readDispatchData是安全的
@property (nonatomic) dispatch_data_t writeDispatchData;
@property (nonatomic) dispatch_data_t readDispatchData;

@end

@implementation WebSocketManager

- (void)dealloc{
    NSLog(@"%s",__FUNCTION__);
    
    [NSNotificationCenter.defaultCenter removeObserver:self name:WebSocket_Notification_Status_Code_Change object:nil];
}

- (instancetype)initWith:(id<WebSocketDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _readDispatchData = dispatch_data_empty;
        _writeDispatchData = dispatch_data_empty;
        _readQueue = dispatch_queue_create("WebSocketManager.Read.Queue", DISPATCH_QUEUE_SERIAL);
        _writeQueue = dispatch_queue_create("WebSocketManager.Write.Queue", DISPATCH_QUEUE_SERIAL);
        _fileManager = [[WebSocketFileManager alloc] initWith:self];
        _deserialization = [[WebSocketDeserialization alloc] initWith:self];
        
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(notificationStatusCode:) name:WebSocket_Notification_Status_Code_Change object:nil];
    }
    return self;
}

#pragma mark - Connection

- (void)connect:(NSString *)urlString{
    _socketProxy = [[WebSocketProxy alloc] initWith:urlString delegate:self];
    [_socketProxy connect];
}

- (void)reconnect{
    
}

- (void)disConnect:(NSString *)text{
    if (self.isConnected) {
        __weak typeof(self) weakSelf = self;
        SendData([text dataUsingEncoding:NSUTF8StringEncoding], Close_OPCode, ^(NSData *data) {
            [weakSelf finishSerializeToSend:data];
        });
    }
}

- (void)closeStream{
    NSLog(@"%s",__FUNCTION__);
    Code_Connection = Status_Code_Connection_Close;
    [_fileManager closeStream];
    [_outputStream close];
    [_inputStream close];
    [_inputStream removeFromRunLoop:Thread.shareInstance.runLoop forMode:NSDefaultRunLoopMode];
    [_outputStream removeFromRunLoop:Thread.shareInstance.runLoop forMode:NSDefaultRunLoopMode];
}

#pragma mark - Operation

- (void)sendText:(NSString *)text{
    if (self.isConnected) {
        __weak typeof(self) weakSelf = self;
        SendData([text dataUsingEncoding:NSUTF8StringEncoding], TextFrame_OPCode, ^(NSData *data) {
            [weakSelf finishSerializeToSend:data];
        });
    }
}

- (void)sendPing:(NSString *)text{
    if (self.isConnected) {
        __weak typeof(self) weakSelf = self;
        SendData([text dataUsingEncoding:NSUTF8StringEncoding], Ping_OPCode, ^(NSData *data) {
            [weakSelf finishSerializeToSend:data];
        });
    }
}

- (void)sendPong:(NSString *)text{
    if (self.isConnected) {
        __weak typeof(self) weakSelf = self;
        SendData([text dataUsingEncoding:NSUTF8StringEncoding], Pong_OPCode, ^(NSData *data) {
            [weakSelf finishSerializeToSend:data];
        });
    }
}

- (void)sendFile:(NSString *)filePath{
    if (self.isConnected) {
        [_fileManager sendFile:filePath];
    }
}

#pragma mark - Read And Write

- (void)writeData:(dispatch_data_t)dispatchData{
    dispatch_async(_writeQueue, ^{
        self.writeDispatchData = dispatch_data_create_concat(self.writeDispatchData, dispatchData);
        
        __block size_t sumOffset = 0;
        dispatch_data_apply(self.writeDispatchData, ^bool(dispatch_data_t  _Nonnull region, size_t offset, const void * _Nonnull buffer, size_t size) {
            NSInteger length = [self.outputStream write:buffer maxLength:size];
            sumOffset += length ? length : 0;
            
            return length < size ? NO : YES;
        });
        
        self.writeDispatchData = dispatch_data_create_subrange(self.writeDispatchData, sumOffset, dispatch_data_get_size(self.writeDispatchData) - sumOffset);
    });
}

- (void)readData{
    dispatch_async(_readQueue, ^{
        int size = getpagesize();
        uint8_t buffer[size];
        
        while (self.inputStream.hasBytesAvailable) {
            NSInteger length = [self.inputStream read:buffer maxLength:size];
            if (length) {
                dispatch_data_t tempData = dispatch_data_create(buffer, length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                
                [self.shareCondition lock];
                self.readDispatchData = dispatch_data_create_concat(self.writeDispatchData, tempData);
                [self.shareCondition signal];   //通知等待信号
                [self.shareCondition unlock];
            }
        }
        
        [self.deserialization receiveData:self.readDispatchData];
    });
}

#pragma mark - Notification

- (void)notificationStatusCode:(NSNotification *)notification{
    if (self.isConnected) {
        [self reconnect];
    }
}

#pragma mark - WebSoketProtocol

- (void)finishSerializeToSend:(NSData *)data{
    dispatch_data_t tempData = dispatch_data_create(data.bytes, data.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    [self writeData:tempData];
}

- (void)finishDeserializeError:(NSError *)error{
    NSLog(@"%@",error.domain);
}

- (void)finishDeserializeFile:(NSString *)filePath{
    ![_delegate respondsToSelector:@selector(didReceiveFile:)] ? : [_delegate didReceiveFile:filePath];
}

- (void)saveData:(NSData *)data isFinish:(BOOL)isFinish{
    [_fileManager writeData:data isFinish:isFinish];
}

- (void)finishDeserializeString:(NSString *)text opCode:(OPCode)opCode{
    switch (opCode) {
        case Close_OPCode:
            [self closeStream];
            break;
        case Ping_OPCode:
            [self sendPong:@"Heartbeat to you!"];
            break;
        default:{
            dispatch_async(dispatch_get_main_queue(), ^{
                ![self.delegate respondsToSelector:@selector(didReceiveText:)] ? : [self.delegate didReceiveText:text];
            });
        }
            break;
    }
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode{
    switch (eventCode) {
        case NSStreamEventHasBytesAvailable:
            NSLog(@"NSStreamEventHasBytesAvailable");
            [self readData];
            break;
        case NSStreamEventHasSpaceAvailable:
            NSLog(@"NSStreamEventHasSpaceAvailable");
            [self writeData:dispatch_data_empty];
            break;
        case NSStreamEventErrorOccurred:
            NSLog(@"NSStreamEventErrorOccurred");
            [self disConnect:@"StreamEvent Error Occurred!"];
            break;
        default:
            break;
    }
}

#pragma mark - NSStreamDelegate

- (void)didConnect:(NSInputStream *)inputStream outputStream:(NSOutputStream *)outputStream error:(NSError *)error{
    !error ? : NSLog(@"%@",error.domain);
    _socketProxy = nil;
    _inputStream = inputStream;
    _outputStream = outputStream;
    _inputStream.delegate = self;
    _outputStream.delegate = self;
    Code_Connection = Status_Code_Connection_Normal;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        ![self.delegate respondsToSelector:@selector(didConnectWebSocket)] ? : [self.delegate didConnectWebSocket];
    });
}

- (NSCondition *)shareCondition{
    return ShareCondition();
}

- (BOOL)isConnected{
    return ShouldWhile();
}

@end
