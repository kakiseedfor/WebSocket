//
//  WebSocketManager.h
//  WebSocket
//
//  Created by kakiYen on 2019/5/21.
//  Copyright © 2019 kakiYen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WebSocketFileManager.h"

@interface WebSocketManager : NSObject

- (BOOL)isConnected;

- (void)connect:(NSString *)urlString;

- (void)disConnect:(NSString *)text;

- (void)sendText:(NSString *)text;

- (void)sendFile:(NSString *)filePath;

- (instancetype)initWith:(id<WebSocketDelegate>)delegate;

@end
