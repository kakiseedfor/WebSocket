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
@property (strong, nonatomic) WebSocketReachability *reachability;
@property (strong, nonatomic) WebSocketFileManager *fileManager;
@property (strong, nonatomic) WebSocketProxy *socketProxy;
@property (strong, nonatomic) NSOutputStream *outputStream;
@property (strong, nonatomic) NSInputStream *inputStream;
@property (nonatomic) dispatch_queue_t writeQueue;  //考虑到弱网、无网情况及实时发送特殊的OPCode；确保每个线程对writeDispatchData是安全的
@property (nonatomic) dispatch_queue_t readQueue;  //考虑到弱网情况，需要形成生产消费者模式；确保每个线程对readDispatchData是安全的
@property (nonatomic) dispatch_data_t writeDispatchData;
@property (nonatomic) dispatch_data_t readDispatchData;
@property (nonatomic) dispatch_source_t timer;
@property (nonatomic) NSInteger heartbeat;

@end

@implementation WebSocketManager

- (void)dealloc{
    NSLog(@"%s",__FUNCTION__);
    
    [self closeStream];
}

- (instancetype)initWith:(id<WebSocketDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _heartbeat = 0;
        _readDispatchData = dispatch_data_empty;
        _writeDispatchData = dispatch_data_empty;
        _readQueue = dispatch_queue_create("WebSocketManager.Read.Queue", DISPATCH_QUEUE_SERIAL);
        _writeQueue = dispatch_queue_create("WebSocketManager.Write.Queue", DISPATCH_QUEUE_SERIAL);
        _socketProxy = [[WebSocketProxy alloc] initWith:self];
        _fileManager = [[WebSocketFileManager alloc] initWith:self];
        _deserialization = [[WebSocketDeserialization alloc] initWith:self];
    }
    return self;
}

#pragma mark - Connection

- (void)connect:(NSString *)urlString{
    if (Code_Connection == Status_Code_Connection_Close) {
        Code_Connection = Status_Code_Connection_Doing;
        
        _reachability = [WebSocketReachability reachabilityForInternetConnection];
        [_reachability  startNotifier];
        [_socketProxy connect:urlString];
        
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(notificationStatusCode:) name:kReachabilityChangedNotification object:nil];
    }
}

- (void)reconnect{
    [_socketProxy reconnect];
}

- (void)disConnect:(NSString *)text{
    if (self.isConnected) {
        WSSeakSelf;
        SendData([text dataUsingEncoding:NSUTF8StringEncoding], Close_OPCode, ^(NSData *data) {
            [wsseakSelf finishSerializeToSend:data];
        });
    }
}

- (void)closeStream{
    Code_Connection = Status_Code_Connection_Close;
    
    !_timer ? : dispatch_source_cancel(_timer);
    [_reachability stopNotifier];
    [_fileManager closeStream];
    [_outputStream close];
    [_inputStream close];
    [_inputStream removeFromRunLoop:Thread.shareInstance.runLoop forMode:NSDefaultRunLoopMode];
    [_outputStream removeFromRunLoop:Thread.shareInstance.runLoop forMode:NSDefaultRunLoopMode];
    [NSNotificationCenter.defaultCenter removeObserver:self name:kReachabilityChangedNotification object:nil];
    
    _heartbeat = 0;
    _inputStream = nil;
    _outputStream = nil;
    _readDispatchData = dispatch_data_empty;
    _writeDispatchData = dispatch_data_empty;
}

#pragma mark - Operation

- (void)sendText:(NSString *)text{
    if (self.isConnected && text.length) {
        WSSeakSelf;
        SendData([text dataUsingEncoding:NSUTF8StringEncoding], TextFrame_OPCode, ^(NSData *data) {
            [wsseakSelf finishSerializeToSend:data];
        });
    }
}

- (void)sendPing:(NSString *)text{
    if (self.isConnected) {
        !_timer ? : dispatch_source_cancel(_timer);
        
        _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
        dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC, 0);
        
        WSSeakSelf;
        dispatch_source_set_event_handler(_timer, ^{
            NSError *error = nil;
            if (wsseakSelf.heartbeat < 3) { //心跳包连续超时超过3次，即视为服务端端开链接
                SendData([text dataUsingEncoding:NSUTF8StringEncoding], Ping_OPCode, ^(NSData *data) {
                    [wsseakSelf finishSerializeToSend:data];
                });
            }else{
                error = [NSError errorWithDomain:@"The Service has not response Ping Code!" code:Status_Code_Connection_Error userInfo:@{}];
                [wsseakSelf finishDeserializeError:error];
            }
            
            error ? : dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{  //心跳包超过3秒即为超时
                wsseakSelf.heartbeat++;
            });
        });
        dispatch_resume(_timer);
    }
}

- (void)sendPong:(NSString *)text{
    if (self.isConnected) {
        WSSeakSelf;
        SendData([text dataUsingEncoding:NSUTF8StringEncoding], Pong_OPCode, ^(NSData *data) {
            [wsseakSelf finishSerializeToSend:data];
        });
    }
}

- (void)sendFile:(NSString *)filePath{
    if (self.isConnected) {
        [_fileManager sendFile:filePath];
    }
}

- (void)sendData:(NSData *)data{
    if (self.isConnected) {
        [_fileManager sendData:data];
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
                self.readDispatchData = dispatch_data_create_concat(self.readDispatchData, tempData);
                [self.shareCondition signal];   //通知等待信号
                [self.shareCondition unlock];
            }
        }
        
        [self.deserialization receiveData:&self->_readDispatchData];
    });
}

#pragma mark - Notification

- (void)notificationStatusCode:(NSNotification *)notification{
    switch (_reachability.currentReachabilityStatus) {
        case NotReachable:{
            NSError *error = [NSError errorWithDomain:@"The connection is invalid!" code:Status_Code_Connection_Invalid userInfo:@{}];
            [self finishDeserializeError:error];
        }
            break;
        default:
            self.isConnected ? : [self reconnect];
            break;
    }
}

#pragma mark - WebSoketProtocol

- (void)finishSerializeToSend:(NSData *)data{
    dispatch_data_t tempData = dispatch_data_create(data.bytes, data.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    [self writeData:tempData];
}

- (void)finishDeserializeError:(NSError *)error{
    switch (error.code) {
        case Status_Code_Connection_Invalid:{
            [self closeStream];
            ![_delegate respondsToSelector:@selector(connectionWithError:)] ? : [_delegate connectionWithError:error];
        }
            break;
        case Status_Code_Connection_Close:
        case Status_Code_Connection_Error:
            [self finishDeserializeString:@"" opCode:Close_OPCode];
            break;
        default:
            break;
    }
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
        case Pong_OPCode:
            _heartbeat--;
            break;
        case Ping_OPCode:
            [self sendPong:@""];
            break;
        case Close_OPCode:{
            [self closeStream];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                ![self.delegate respondsToSelector:@selector(didCloseWebSocket)] ? : [self.delegate didCloseWebSocket];
            });
        }
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
            [self readData];
            break;
        case NSStreamEventHasSpaceAvailable:
            [self writeData:dispatch_data_empty];
            break;
        case NSStreamEventErrorOccurred:
            [self disConnect:@"StreamEvent Error Occurred!"];
            break;
        default:
            break;
    }
}

#pragma mark - NSStreamDelegate

- (void)didConnect:(NSInputStream *)inputStream outputStream:(NSOutputStream *)outputStream error:(NSError *)error{
    _inputStream = inputStream;
    _outputStream = outputStream;
    _inputStream.delegate = self;
    _outputStream.delegate = self;
    
    if (error) {
        Code_Connection = Status_Code_Connection_Close;
        [self finishDeserializeError:error];
    }else{
        Code_Connection = Status_Code_Connection_Normal;
        
        [self sendPing:@""];
        dispatch_async(dispatch_get_main_queue(), ^{
            ![self.delegate respondsToSelector:@selector(didConnectWebSocket)] ? : [self.delegate didConnectWebSocket];
        });
    }
}

- (NSCondition *)shareCondition{
    return ShareCondition();
}

- (BOOL)isConnected{
    return Code_Connection == Status_Code_Connection_Normal;
}

@end
