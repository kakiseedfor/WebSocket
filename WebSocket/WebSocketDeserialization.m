//
//  WebSocketDeserialization.m
//  WebSocket
//
//  Created by kakiYen on 2019/5/22.
//  Copyright © 2019 kakiYen. All rights reserved.
//

#import "WebSocketDeserialization.h"
#import "WebSocketHeader.h"

extern STATUS_CODE Code_Connection;

@interface WebSocketDeserialization ()
@property (weak, nonatomic) id<WebSoketProtocol> delegate;
@property (nonatomic) dispatch_queue_t queue;
@property (nonatomic) dispatch_data_t buffer;

@end

@implementation WebSocketDeserialization

- (void)dealloc
{
    NSLog(@"%s",__FUNCTION__);
}

- (instancetype)initWith:(id<WebSoketProtocol>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _buffer = dispatch_data_empty;
        _queue = dispatch_queue_create("WebSocket.Deserialization.Queue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)receiveData:(dispatch_data_t __strong*)tempData{
    dispatch_async(_queue, ^{
        [self.shareCondition lock];
        
        dispatch_data_t data = *tempData;
        const uint8_t *bytes = ((NSData *)data).bytes;
        if (dispatch_data_get_size(data) < 2) {
            
        }else if (bytes[0] & RSV_ONE_MASK || bytes[0] & RSV_TWO_MASK || bytes[0] & RSV_THREE_MASK) {
            NSError *error = [NSError errorWithDomain:@"Status Code Protocol Error" code:Status_Code_Protocol_Error userInfo:nil];
            ![self.delegate respondsToSelector:@selector(finishDeserializeError:)] ? : [self.delegate finishDeserializeError:error];
        }else{
            [self dealData:tempData];
        }
        
        [self.shareCondition unlock];
    });
}

- (void)dealData:(dispatch_data_t __strong*)data{
    NSError *error = nil;
    const uint8_t *bytes = ((NSData *)*data).bytes;
    
    static OPCode opCode = Continue_OPCode; //用来区分数据类型
    BOOL control = ((bytes[0] & Close_OPCode) == Close_OPCode || (bytes[0] & Pong_OPCode) == Pong_OPCode || (bytes[0] & Ping_OPCode) == Ping_OPCode) && bytes[0] & FIN_FINAL_MASK;
    if (control || bytes[0] & TextFrame_OPCode || bytes[0] & BinaryFrame_OPCode || (bytes[0] & None_OPCode) == Continue_OPCode) {
        opCode = opCode ? opCode : (bytes[0] & TextFrame_OPCode);
        opCode = opCode ? opCode : (bytes[0] & BinaryFrame_OPCode);
        
        size_t payload = bytes[1] & PAY_LOAD_127;
        size_t maskLength = bytes[1] & MASKKEY_MASK ? sizeof(uint32_t) : 0;
        size_t extendLength = payload < PAY_LOAD_126 ? 0 : (payload == PAY_LOAD_126 ? sizeof(uint16_t) : sizeof(uint64_t));
        
        size_t header = sizeof(uint16_t) + extendLength + maskLength;
        while (self.isConnected && dispatch_data_get_size(*data) < header) {
            [self.shareCondition wait];
        }
        
        if (!self.isConnected) {
            error = [NSError errorWithDomain:@"Status Code Connection Close" code:Status_Code_Connection_Close userInfo:nil];
            _buffer = dispatch_data_empty;
            ![self.delegate respondsToSelector:@selector(finishDeserializeError:)] ? : [self.delegate finishDeserializeError:error];
            return;
        }
        
        if (extendLength) {
            dispatch_data_t subData = dispatch_data_create_subrange(*data, sizeof(uint16_t), extendLength);
            const uint8_t *subBytes = ((NSData *)subData).bytes;
            
            uint64_t tempload = 0;
            memcpy(&tempload, subBytes, extendLength);
            payload = (payload == PAY_LOAD_126 ? CFSwapInt16BigToHost(tempload) : CFSwapInt64BigToHost(tempload));
        }
        
        uint8_t *mask = NULL;
        if (maskLength) {
            uint8_t tempMask[maskLength];
            dispatch_data_t subData = dispatch_data_create_subrange(*data, header - maskLength, maskLength);
            const uint8_t *subBytes = ((NSData *)subData).bytes;
            memcpy(tempMask, subBytes, maskLength);
            mask = tempMask;
        }
        
        *data = dispatch_data_create_subrange(*data, header, dispatch_data_get_size(*data) - header);
        while (self.isConnected && dispatch_data_get_size(*data) < payload) {
            [self.shareCondition wait];
        }
        
        if (!self.isConnected) {
            error = [NSError errorWithDomain:@"Status Code Connection Close" code:Status_Code_Connection_Close userInfo:nil];
            _buffer = dispatch_data_empty;
            ![self.delegate respondsToSelector:@selector(finishDeserializeError:)] ? : [self.delegate finishDeserializeError:error];
            return;
        }
        
        dispatch_data_t payloadData = dispatch_data_create_subrange(*data, 0, payload);
        payloadData == dispatch_data_empty || maskLength <= 0 ? : MaskByteWith((uint8_t *)((NSData *)payloadData).bytes, mask, payload);
        
        _buffer = dispatch_data_create_concat(_buffer, payloadData);
        if (bytes[0] & FIN_FINAL_MASK) {
            if (control) {
                OPCode controlCode = bytes[0] & None_OPCode;
                
                NSString *string = [[NSString alloc] initWithData:(NSData *)_buffer encoding:NSUTF8StringEncoding];
                
                ![_delegate respondsToSelector:@selector(finishDeserializeString:opCode:)] ? : [_delegate finishDeserializeString:string opCode:controlCode];
            }else{
                switch (opCode) {
                    case TextFrame_OPCode:{
                        NSString *string = [[NSString alloc] initWithData:(NSData *)_buffer encoding:NSUTF8StringEncoding];
                        
                        if (string.length) {
                            ![self.delegate respondsToSelector:@selector(finishDeserializeString:opCode:)] ? : [self.delegate finishDeserializeString:string opCode:opCode];
                        }else{
                            error = [NSError errorWithDomain:@"Status Code Invalid UTF8" code:Status_Code_Invalid_UTF8 userInfo:nil];
                            ![self.delegate respondsToSelector:@selector(finishDeserializeError:)] ? : [self.delegate finishDeserializeError:error];
                        }
                    }
                        break;
                    case BinaryFrame_OPCode:{
                        ![_delegate respondsToSelector:@selector(saveData:isFinish:)] ? : [_delegate saveData:(NSData *)_buffer isFinish:YES];
                    }
                        break;
                    default:
                        break;
                }
            }
            
            opCode = Continue_OPCode;
            _buffer = dispatch_data_empty;
        }else if (opCode == BinaryFrame_OPCode) {
            ![_delegate respondsToSelector:@selector(saveData:isFinish:)] ? : [_delegate saveData:(NSData *)_buffer isFinish:NO];
            _buffer = dispatch_data_empty;
        }
        
        *data = dispatch_data_create_subrange(*data, payload, dispatch_data_get_size(*data) - payload);
        if (dispatch_data_get_size(*data)) {
            [self receiveData:data];
        }
    }else{
        opCode = Continue_OPCode;
        _buffer = dispatch_data_empty;
        error = [NSError errorWithDomain:@"Status Code Protocol Error" code:Status_Code_Protocol_Error userInfo:nil];
        ![self.delegate respondsToSelector:@selector(finishDeserializeError:)] ? : [self.delegate finishDeserializeError:error];
    }
}

- (NSCondition *)shareCondition{
    return ShareCondition();
}

- (BOOL)isConnected{
    return Code_Connection == Status_Code_Connection_Normal;
}

@end
