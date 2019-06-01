//
//  WebSocketProxy.h
//  WebSocket
//
//  Created by kakiYen on 2019/5/29.
//  Copyright © 2019 kakiYen. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol WebSocketProxyDelegate <NSObject>

- (void)didConnect:(NSInputStream *)inputStream outputStream:(NSOutputStream *)outputStream error:(NSError *)error;

@end

@interface WebSocketProxy : NSObject

- (instancetype)initWith:(NSString *)urlString delegate:(id<WebSocketProxyDelegate>)delegate;

- (void)connect;

@end
