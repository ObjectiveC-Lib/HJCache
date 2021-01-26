//
//  HJCommonCache.m
//  HJCache
//
//  Created by navy on 2019/3/6.
//

#import "HJCommonCache.h"
#import "HJMemoryCache.h"
#import "HJDiskCache.h"

@implementation HJCommonCache

#pragma mark - Initializer

- (instancetype)init {
    @throw [NSException exceptionWithName:@"HJCommonCache init error"
                                   reason:@"HJCommonCache must be initialized with a path. Use 'initWithPath:' instead."
                                 userInfo:nil];
    return [self initWithPath:@""];
}

- (nullable instancetype)initWithPath:(NSString *)path {
    if (path.length == 0) return nil;
    
    NSString *name = [path lastPathComponent];
    HJDiskCache *diskCache = [[HJDiskCache alloc] initWithPath:path];
    diskCache.name = name;
    
    HJMemoryCache *memoryCache = [HJMemoryCache new];
    memoryCache.name = name;
    if (!diskCache || !memoryCache) return nil;
    
    self = [super init];
    _diskCache = diskCache;
    _memoryCache = memoryCache;
    
    return self;
}

+ (instancetype)sharedCache {
    static HJCommonCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *cachePath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                                   NSUserDomainMask, YES) firstObject];
        cachePath = [cachePath stringByAppendingPathComponent:@"HJCache"];
        cachePath = [cachePath stringByAppendingPathComponent:@"HJCommonCache"];
        cache = [[self alloc] initWithPath:cachePath];
    });
    return cache;
}

#pragma mark - Access Methods

- (BOOL)containsObjectForKey:(NSString *)key {
    return [_memoryCache containsObjectForKey:key] || [_diskCache containsObjectForKey:key];
}

- (void)containsObjectForKey:(NSString *)key withBlock:(nullable void(^)(NSString *key, BOOL contains))block {
    if (!block) return;

    if ([_memoryCache containsObjectForKey:key]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            block(key, YES);
        });
    } else {
        [_diskCache containsObjectForKey:key withBlock:block];
    }
}

- (nullable id<NSCoding>)objectForKey:(NSString *)key {
    id<NSCoding> object = [_memoryCache objectForKey:key];
    if (!object) {
        object = [_diskCache objectForKey:key];
        if (object) {
            [_memoryCache setObject:object forKey:key];
        }
    }
    return object;
}

- (void)objectForKey:(NSString *)key withBlock:(nullable void(^)(NSString *key, id<NSCoding> object))block {
    if (!block) return;
    id<NSCoding> object = [_memoryCache objectForKey:key];
    if (object) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            block(key, object);
        });
    } else {
        [_diskCache objectForKey:key withBlock:^(NSString *key, id<NSCoding> object) {
            if (object && ![self->_memoryCache objectForKey:key]) {
                [self->_memoryCache setObject:object forKey:key];
            }
            block(key, object);
        }];
    }
}

- (void)setObject:(nullable id<NSCoding>)object forKey:(NSString *)key {
    [_memoryCache setObject:object forKey:key];
    [_diskCache setObject:object forKey:key];
}

- (void)setObject:(nullable id<NSCoding>)object forKey:(NSString *)key withBlock:(nullable void(^)(void))block {
    [_memoryCache setObject:object forKey:key];
    [_diskCache setObject:object forKey:key withBlock:block];
}

- (void)removeObjectForKey:(NSString *)key {
    [_memoryCache removeObjectForKey:key];
    [_diskCache removeObjectForKey:key];
}

- (void)removeObjectForKey:(NSString *)key withBlock:(nullable void(^)(NSString *key))block {
    [_memoryCache removeObjectForKey:key];
    [_diskCache removeObjectForKey:key withBlock:block];
}

- (void)removeAllObjects {
    [_memoryCache removeAllObjects];
    [_diskCache removeAllObjects];
}

- (void)removeAllObjectsWithBlock:(void(^)(void))block {
    [_memoryCache removeAllObjects];
    [_diskCache removeAllObjectsWithBlock:block];
}

- (void)removeAllObjectsWithProgressBlock:(nullable void(^)(int removedCount, int totalCount))progress
                                 endBlock:(nullable void(^)(BOOL error))end {
    [_memoryCache removeAllObjects];
    [_diskCache removeAllObjectsWithProgressBlock:progress endBlock:end];
}

@end
