//
//  WebSocketFileManager.h
//  WebSocket
//
//  Created by kakiYen on 2019/5/24.
//  Copyright © 2019 kakiYen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WebSocketDeserialization.h"

@interface WebSocketFileManager : NSObject

- (instancetype)initWith:(id<WebSoketProtocol>)delegate;

- (void)writeData:(NSData *)data isFinish:(BOOL)isFinish;

- (void)sendFile:(NSString *)filePath;

- (void)closeStream;

@end
