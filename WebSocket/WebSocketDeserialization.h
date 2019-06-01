//
//  WebSocketDeserialization.h
//  WebSocket
//
//  Created by kakiYen on 2019/5/22.
//  Copyright © 2019 kakiYen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WebSocketUtility.h"

@interface WebSocketDeserialization : NSObject

- (instancetype)initWith:(id<WebSoketProtocol>)delegate;

- (void)receiveData:(dispatch_data_t)data;

@end
