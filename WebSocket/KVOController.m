//
//  KVOController.m
//  LockProject
//
//  Created by kakiYen on 2019/3/30.
//  Copyright © 2019 kakiYe. All rights reserved.
//

#import "NSObject+KVOObject.h"
#import "KVOController.h"
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark KVOInfo

@interface KVOInfo : NSObject
@property (weak, nonatomic) id observe;
@property (copy, nonatomic) KVOCallBack callBack;
@property (strong, nonatomic) NSString *keyPath;
@property (strong, nonatomic) KVOObserve *kvoObserve;
@property (nonatomic) NSKeyValueObservingOptions option;

@end

@implementation KVOInfo

- (void)dealloc{
    NSLog(@"%s",__FUNCTION__);
}

- (instancetype)initWith:(id)observe keyPath:(NSString *)keyPath option:(NSKeyValueObservingOptions)option kvoCallBack:(KVOCallBack)kvoCallBack
{
    self = [super init];
    if (self) {
        _option = option;
        _observe = observe;
        _keyPath = keyPath;
        _callBack = kvoCallBack;
        _kvoObserve = [[KVOObserve alloc] init];
    }
    return self;
}

@end

#pragma mark KVOObserve

@implementation KVOObserve

- (void)dealloc{
    NSLog(@"%s",__FUNCTION__);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    KVOInfo *info = (__bridge KVOInfo *)(context);
    if (info.callBack) {
        id tempContext = nil;
        
        if (info.option & NSKeyValueObservingOptionOld) {
            tempContext = change[@"old"];
            info.callBack(tempContext);
        }
        
        if (info.option & NSKeyValueObservingOptionNew) {
            tempContext = change[@"new"];
            info.callBack(tempContext);
        }
    }
}

@end

#pragma mark KVOController

@interface KVOController ()
@property (nonatomic) CFRunLoopObserverRef observerRef;
@property (weak, nonatomic) NSObject *original;
@property (strong, nonatomic) NSMutableArray<KVOInfo *> *kvoInfos;

@end

@implementation KVOController

- (void)dealloc{
    NSLog(@"%s",__FUNCTION__);
    CFRunLoopRemoveObserver(CFRunLoopGetCurrent(), self.observerRef, kCFRunLoopDefaultMode);
    CFRelease(self.observerRef);
    [self removeAllObserver];
}

- (instancetype)initWith:(NSObject *)original
{
    self = [super init];
    if (self) {
        _original = original;
        _kvoInfos = [NSMutableArray array];
        
        [self addObserver];
    }
    return self;
}

- (void)addObserver{
    __weak typeof(self) weakSelf = self;
    self.observerRef = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, 0xa0, YES, INT_MAX, ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
        [weakSelf updateKVOInfos];
    });
    
    CFRunLoopAddObserver(CFRunLoopGetCurrent(), self.observerRef, kCFRunLoopDefaultMode);
}

- (void)updateKVOInfos{
    NSMutableArray *tempArray = [NSMutableArray array];
    
    [self.kvoInfos enumerateObjectsUsingBlock:^(KVOInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (!obj.observe) {
            [self.original removeObserver:obj.kvoObserve forKeyPath:obj.keyPath context:(void *)obj];
            [tempArray addObject:obj];
        }
    }];
    
    [self.kvoInfos removeObjectsInArray:tempArray];
}

- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options kvoCallBack:(KVOCallBack)kvoCallBack
{
    NSMutableArray *keyPathArray = [keyPath componentsSeparatedByString:@"."].mutableCopy;
    
    NSString *tempKeyPath = keyPathArray.firstObject;
    NSAssert([self classForKeyPath:self.original.class keyPath:tempKeyPath], @"Adding observer With %@ is invalid keyPath",tempKeyPath);
    
    [keyPathArray removeObject:tempKeyPath];
    if (keyPathArray.count) {
        keyPath = [keyPathArray componentsJoinedByString:@"."];
        
        id value = [self.original valueForKey:tempKeyPath];
        [[value kvoController] addObserver:observer forKeyPath:keyPath options:options kvoCallBack:kvoCallBack];
    }else{
        KVOInfo *info = [[KVOInfo alloc] initWith:observer keyPath:tempKeyPath option:options kvoCallBack:kvoCallBack];
        [self.kvoInfos addObject:info];
        [self.original addObserver:info.kvoObserve forKeyPath:tempKeyPath options:options context:(void *)info];
    }
}

- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath{
    NSMutableArray *tempArray = [NSMutableArray array];
    
    [_kvoInfos enumerateObjectsUsingBlock:^(KVOInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        BOOL should = [obj.observe isEqual:observer] && (keyPath.length ? [obj.keyPath isEqualToString:keyPath] : YES);
        
        if (should) {
            [self.original removeObserver:obj.kvoObserve forKeyPath:obj.keyPath context:(void *)obj];
            [tempArray addObject:obj];
        }
    }];
    
    [self.kvoInfos removeObjectsInArray:tempArray];
}

- (void)removeObserver:(NSObject *)observer{
    [self removeObserver:observer forKeyPath:@""];
}

- (void)removeAllObserver{
    [_kvoInfos enumerateObjectsUsingBlock:^(KVOInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [self.original removeObserver:obj.kvoObserve forKeyPath:obj.keyPath context:(void *)obj];
    }];
    
    [_kvoInfos removeAllObjects];
}

- (BOOL)checkKeyPath:(NSString *)keyPath{
    return [self classForKeyPath:self.original.class keyPath:keyPath];
}

- (BOOL)classForKeyPath:(Class)objClass keyPath:(NSString *)keyPath{
    BOOL valid = NO;
    
    uint count = 0;
    objc_property_t *propertyList = class_copyPropertyList(objClass, &count);
    for (int i = 0; i < count; i++) {
        const char *attributes = property_getName(propertyList[i]);
        char *result = strstr(attributes, keyPath.UTF8String);
        
        if (result) {
            valid = YES;
            NSLog(@"%s",attributes);
            break;
        }
    }
    
    if (!valid) {
        Class superClass = class_getSuperclass(objClass);
        valid = superClass ? [self classForKeyPath:superClass keyPath:keyPath] : NO;
    }
    
    return valid;
}

@end
