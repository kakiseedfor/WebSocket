//
//  NSObject+KVOObject.m
//  LockProject
//
//  Created by kakiYen on 2019/3/30.
//  Copyright © 2019 kakiYe. All rights reserved.
//

#import "NSObject+KVOObject.h"
#import <objc/runtime.h>

static NSString *NSObjectKVOControllerKey = @"NSObjectKVOControllerKey";

@implementation NSObject (KVOObject)

- (KVOController *)kvoController{
    KVOController *tempObj = objc_getAssociatedObject(self, &NSObjectKVOControllerKey);
    
    if (!tempObj) {
        tempObj = [[KVOController alloc] initWith:self];
        self.kvoController = tempObj;
    }
    
    return tempObj;
}

- (void)setKvoController:(KVOController *)kvoController{
    objc_setAssociatedObject(self, &NSObjectKVOControllerKey, kvoController, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
