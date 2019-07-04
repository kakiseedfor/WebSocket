//
//  NSObject+KVOObject.h
//  LockProject
//
//  Created by kakiYen on 2019/3/30.
//  Copyright © 2019 kakiYe. All rights reserved.
//


#import "KVOController.h"

@interface NSObject (KVOObject)
@property (strong, nonatomic) KVOController *kvoController;

@end
