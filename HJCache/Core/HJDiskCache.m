//
//  HJDiskCache.m
//  HJCache
//
//  Created by navy on 2019/3/4.
//

#import "HJDiskCache.h"
#import "HJKVStorage.h"
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonCrypto.h>
#import <objc/runtime.h>
#import <time.h>
#import <pthread/pthread.h>

#define Lock() pthread_mutex_lock(&_lock)
#define Unlock() pthread_mutex_unlock(&_lock)

static const int extended_data_key;

/// Free disk space in bytes.
static int64_t _HJDiskSpaceFree(void) {
    NSError *error = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:&error];
    if (error) return -1;
    int64_t space = [[attrs objectForKey:NSFileSystemFreeSize] longLongValue];
    if (space < 0) space = -1;
    return space;
}

/// String's md5 hash.
#define HJ_MAX_FILE_EXTENSION_LENGTH (NAME_MAX - CC_MD5_DIGEST_LENGTH * 2 - 1)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static inline NSString * _Nonnull _HJFileNameForKey(NSString * _Nullable key) {
    const char *str = key.UTF8String;
    if (str == NULL) {
        str = "";
    }
    unsigned char r[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), r);
    NSURL *keyURL = [NSURL URLWithString:key];
    NSString *ext = keyURL ? keyURL.pathExtension : key.pathExtension;
    // File system has file name length limit, we need to check if ext is too long, we don't add it to the filename
    if (ext.length > HJ_MAX_FILE_EXTENSION_LENGTH) {
        ext = nil;
    }
    NSString *filename = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%@",
                          r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10],
                          r[11], r[12], r[13], r[14], r[15], ext.length == 0 ? @"" : [NSString stringWithFormat:@".%@", ext]];
    return filename;
}
#pragma clang diagnostic pop


/// weak reference for all instances
static NSMapTable *_globalInstances;
static dispatch_semaphore_t _globalInstancesLock;

static void _HJDiskCacheInitGlobal(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _globalInstancesLock = dispatch_semaphore_create(1);
        _globalInstances = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsWeakMemory capacity:0];
    });
}

static HJDiskCache *_HJDiskCacheGetGlobal(NSString *path) {
    if (path.length == 0) return nil;
    _HJDiskCacheInitGlobal();
    dispatch_semaphore_wait(_globalInstancesLock, DISPATCH_TIME_FOREVER);
    id cache = [_globalInstances objectForKey:path];
    dispatch_semaphore_signal(_globalInstancesLock);
    return cache;
}

static void _HJDiskCacheSetGlobal(HJDiskCache *cache) {
    if (cache.path.length == 0) return;
    _HJDiskCacheInitGlobal();
    dispatch_semaphore_wait(_globalInstancesLock, DISPATCH_TIME_FOREVER);
    [_globalInstances setObject:cache forKey:cache.path];
    dispatch_semaphore_signal(_globalInstancesLock);
}

@implementation HJDiskCache {
    HJKVStorage *_kv;
    pthread_mutex_t _lock;
    dispatch_queue_t _queue;
}

#pragma mark - Private

- (void)_trimRecursively {
    __weak typeof (self) _self = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_autoTrimInterval * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        __strong typeof(_self) self = _self;
        if (!self) return;
        [self _trimInBackground];
        [self _trimRecursively];
    });
}

- (void)_trimInBackground {
    __weak typeof (self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof (_self) self = _self;
        if (!self) return;
        Lock();
        [self _trimToCost:self.costLimit];
        [self _trimToCount:self.countLimit];
        [self _trimToAge:self.ageLimit];
        [self _trimToFreeDiskSpace:self.freeDiskSpaceLimit];
        Unlock();
    });
}

- (void)_trimToCost:(NSUInteger)costLimit {
    if (costLimit >= INT_MAX) return;
    [_kv removeItemsToFitSize:(int)costLimit];
}

- (void)_trimToCount:(NSUInteger)countLimit {
    if (countLimit >= INT_MAX) return;
    [_kv removeItemsToFitCount:(int)countLimit];
}

- (void)_trimToAge:(NSTimeInterval)ageLimit {
    if (ageLimit <= 0) {
        [_kv removeAllItems];
        return;
    }
    long timestamp = time(NULL);
    if (timestamp <= ageLimit) return;
    long age = timestamp - ageLimit;
    if (age >= INT_MAX) return;
    [_kv removeitemsEarlierThanTime:(int)age];
}

- (void)_trimToFreeDiskSpace:(NSUInteger)targetFreeDiskSpace {
    if (targetFreeDiskSpace == 0) return;
    
    int64_t totalBytes = [_kv getItemsSize];
    if (totalBytes <= 0) return;
    
    int64_t diskFreeBytes = _HJDiskSpaceFree();
    if (diskFreeBytes < 0) return;
    
    int64_t needTrimBytes = targetFreeDiskSpace - diskFreeBytes;
    if (needTrimBytes <= 0) return;
    
    int64_t costLimit = totalBytes - needTrimBytes;
    if (costLimit < 0) costLimit = 0;
    [self _trimToCost:(int)costLimit];
}

- (NSString *)_filenameForKey:(NSString *)key {
    NSString *filename = nil;
    if (_customFileNameBlock)  filename = _customFileNameBlock(key);
    if (!filename) filename = _HJFileNameForKey(key);
    return filename;
}

- (void)_appWillBeTerminated {
    Lock();
    _kv = nil;
    Unlock();
}

#pragma mark - Initializer

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillTerminateNotification object:nil];
    pthread_mutex_destroy(&_lock);
}

- (instancetype)init {
    @throw [NSException exceptionWithName:@"HJDiskCache init error"
                                   reason:@"HJDiskCache must be initialized with a path. Use 'initWithPath:' or 'initWithPath:inlineThreshold:' instead."
                                 userInfo:nil];
    return [self initWithPath:@"" inlineThreshold:0];
}

- (nullable instancetype)initWithPath:(NSString *)path {
    return [self initWithPath:path inlineThreshold:1024 * 20]; // 20KB
}

- (nullable instancetype)initWithPath:(NSString *)path inlineThreshold:(NSUInteger)threshold {
    self = [super init];
    if (!self) return nil;
    
    HJDiskCache *globalCache = _HJDiskCacheGetGlobal(path);
    if (globalCache) return globalCache;
    
    HJKVStorageType type;
    if (threshold == 0) {
        type = HJKVStorageTypeFile;
    } else if (threshold == NSUIntegerMax) {
        type = HJKVStorageTypeSQLite;
    } else {
        type = HJKVStorageTypeMixed;
    }
    
    HJKVStorage *kv = [[HJKVStorage alloc] initWithPath:path type:type];
    if (!kv) return nil;
    
    _kv = kv;
    _path = path;
    pthread_mutex_init(&_lock, NULL);
    _queue = dispatch_queue_create("com.hj.cache.disk", DISPATCH_QUEUE_CONCURRENT);
    _inlineThreshold = threshold;
    _countLimit = NSUIntegerMax;
    _costLimit = NSUIntegerMax;
    _ageLimit = DBL_MAX;
    _freeDiskSpaceLimit = 0;
    _autoTrimInterval = 60;
    
    [self _trimRecursively];
    _HJDiskCacheSetGlobal(self);
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_appWillBeTerminated) name:UIApplicationWillTerminateNotification object:nil];
    
    return self;
}

#pragma mark - Access Methods

- (BOOL)containsObjectForKey:(NSString *)key {
    if (!key) return NO;
    Lock();
    BOOL contains = [_kv itemExistForKey:key];
    Unlock();
    return contains;
}

- (void)containsObjectForKey:(NSString *)key withBlock:(void(^)(NSString *key, BOOL contains))block {
    if (!block) return;
    __weak typeof (self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof (_self) self = _self;
        BOOL contains = [self containsObjectForKey:key];
        block(key, contains);
    });
}

- (nullable id<NSCoding>)objectForKey:(NSString *)key {
    if (!key) return nil;
    Lock();
    HJKVStorageItem *item = [_kv getItemForKey:key];
    Unlock();
    if (!item.value) return nil;
    
    id object = nil;
    if (_customUnarchiveBlock) {
        object = _customUnarchiveBlock(item.value);
    } else {
        if (@available(iOS 11, tvOS 11, macOS 10.13, watchOS 4, *)) {
            NSError *error;
            NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:item.value error:&error];
            unarchiver.requiresSecureCoding = NO;
            object = [unarchiver decodeTopLevelObjectForKey:NSKeyedArchiveRootObjectKey error:&error];
            if (error) {
                NSLog(@"NSKeyedUnarchiver unarchive failed with error: %@", error);
            }
        } else {
            @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                object = [NSKeyedUnarchiver unarchiveObjectWithData:item.value];
#pragma clang diagnostic pop
            } @catch (NSException *exception) {
                NSLog(@"NSKeyedUnarchiver unarchive failed with exception: %@", exception);
            }
        }
        
    }
    if (object && item.extendedData) {
        [HJDiskCache setExtendedData:item.extendedData toObject:object];
    }
    return object;
}

- (void)objectForKey:(NSString *)key withBlock:(void(^)(NSString *key, id<NSCoding> _Nullable object))block {
    if (!block) return;
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        id<NSCoding> object = [self objectForKey:key];
        block(key, object);
    });
}


- (void)setObject:(id)object forKey:(NSString *)key {
    if (!key) return;
    if (!object) {
        [self removeObjectForKey:key];
        return;
    }
    
    if (![object conformsToProtocol:@protocol(NSCoding)]) return;
    
    NSData *extendedData = [HJDiskCache getExtendedDataFromObject:object];
    if (extendedData) if (![extendedData conformsToProtocol:@protocol(NSCoding)]) return;
    
    NSData *value = nil;
    if (_customArchiveBlock) {
        value = _customArchiveBlock(object);
    } else {
        if (@available(iOS 11, tvOS 11, macOS 10.13, watchOS 4, *)) {
            NSError *error;
            value = [NSKeyedArchiver archivedDataWithRootObject:object requiringSecureCoding:NO error:&error];
            if (error) {
                NSLog(@"NSKeyedArchiver archive failed with error: %@", error);
            }
        } else {
            @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                value = [NSKeyedArchiver archivedDataWithRootObject:object];
#pragma clang diagnostic pop
            } @catch (NSException *exception) {
                NSLog(@"NSKeyedArchiver archive failed with exception: %@", exception);
            }
        }
    }
    if (!value) return;
    
    Lock();
    HJKVStorageType type = _kv.type;
    Unlock();
    
    NSString *filename = nil;
    if (type != HJKVStorageTypeSQLite) {
        if (value.length > _inlineThreshold) {
            filename = [self _filenameForKey:key];
        }
    }
    
    Lock();
    [_kv saveItemWithKey:key value:value filename:filename extendedData:extendedData];
    Unlock();
}

- (void)setObject:(nullable id<NSCoding>)object forKey:(NSString *)key withBlock:(void(^)(void))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self setObject:object forKey:key];
        if (block) block();
    });
}

- (void)removeObjectForKey:(NSString *)key {
    if (!key) return;
    Lock();
    [_kv removeItemForKey:key];
    Unlock();
}

- (void)removeObjectForKey:(NSString *)key withBlock:(void(^)(NSString *key))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self removeObjectForKey:key];
        if (block) block(key);
    });
}

- (void)removeAllObjects {
    Lock();
    [_kv removeAllItems];
    Unlock();
}

- (void)removeAllObjectsWithBlock:(void(^)(void))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self removeAllObjects];
        if (block) block();
    });
}

- (void)removeAllObjectsWithProgressBlock:(nullable void(^)(int removedCount, int totalCount))progress
                                 endBlock:(nullable void(^)(BOOL error))end {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        if (!self) {
            if (end) end(YES);
            return;
        }
        Lock();
        [self->_kv removeAllItemsWithProgressBlock:progress endBlock:end];
        Unlock();
    });
}

- (NSInteger)totalCount {
    Lock();
    int count = [_kv getItemsCount];
    Unlock();
    return count;
}

- (void)totalCountWithBlock:(void(^)(NSInteger totalCount))block {
    if (!block) return;
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        NSInteger totalCount = [self totalCount];
        block(totalCount);
    });
}

- (NSInteger)totalCost {
    Lock();
    int count = [_kv getItemsSize];
    Unlock();
    return count;
}

- (void)totalCostWithBlock:(void(^)(NSInteger totalCost))block {
    if (!block) return;
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        NSInteger totalCost = [self totalCost];
        block(totalCost);
    });
}

#pragma mark - Trim

- (void)trimToCount:(NSUInteger)count {
    Lock();
    [self _trimToCount:count];
    Unlock();
}

- (void)trimToCount:(NSUInteger)count withBlock:(void(^)(void))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self trimToCount:count];
        if (block) block();
    });
}

- (void)trimToCost:(NSUInteger)cost {
    Lock();
    [self _trimToCost:cost];
    Unlock();
}

- (void)trimToCost:(NSUInteger)cost withBlock:(void(^)(void))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self trimToCost:cost];
        if (block) block();
    });
}

- (void)trimToAge:(NSTimeInterval)age {
    Lock();
    [self _trimToAge:age];
    Unlock();
}

- (void)trimToAge:(NSTimeInterval)age withBlock:(void(^)(void))block {
    __weak typeof(self) _self = self;
    dispatch_async(_queue, ^{
        __strong typeof(_self) self = _self;
        [self trimToAge:age];
        if (block) block();
    });
}

#pragma mark - Extended Data

+ (nullable NSData *)getExtendedDataFromObject:(id)object {
    if (!object) return nil;
    return (NSData *)objc_getAssociatedObject(object, &extended_data_key);
}

+ (void)setExtendedData:(nullable NSData *)extendedData toObject:(id)object {
    if (!object) return;
    objc_setAssociatedObject(object, &extended_data_key, extendedData, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSString *)description {
    if (_name) return [NSString stringWithFormat:@"<%@: %p> (%@:%@)", self.class, self, _name, _path];
    else return [NSString stringWithFormat:@"<%@: %p> (%@)", self.class, self, _path];
}

- (BOOL)errorLogsEnabled {
    Lock();
    BOOL enabled = _kv.errorLogsEnabled;
    Unlock();
    return enabled;
}

- (void)setErrorLogsEnabled:(BOOL)errorLogsEnabled {
    Lock();
    _kv.errorLogsEnabled = errorLogsEnabled;
    Unlock();
}

@end
