//
//  KVOController.h
//  LockProject
//
//  Created by kakiYen on 2019/3/30.
//  Copyright © 2019 kakiYe. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^KVOCallBack)(id context);

@interface KVOObserve : NSObject

@end

@interface KVOController : NSObject

- (instancetype)initWith:(NSObject *)original;

- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options kvoCallBack:(KVOCallBack)kvoCallBack;

- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath;

- (void)removeObserver:(NSObject *)observer;

@end
