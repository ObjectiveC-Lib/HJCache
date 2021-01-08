//
//  HJImageCache.m
//  HJCache
//
//  Created by navy on 2019/3/13.
//  Copyright © 2019 navy. All rights reserved.
//

#import "HJImageCache.h"
#import "HJMemoryCache.h"
#import "HJDiskCache.h"

#if __has_include(<YYImage/YYImage.h>)
#import <YYImage/YYImage.h>
#else
#import "YYImage.h"
#endif

static inline dispatch_queue_t HJCacheImageCacheIOQueue() {
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
}

@interface HJImageCache ()
@property (nullable, copy) NSString *path;

- (NSUInteger)imageCost:(UIImage *)image;
- (UIImage *)imageFromData:(NSData *)data;
@end


@implementation HJImageCache

- (NSUInteger)imageCost:(UIImage *)image {
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return 1;
    CGFloat height = CGImageGetHeight(cgImage);
    size_t bytesPerRow = CGImageGetBytesPerRow(cgImage);
    NSUInteger cost = bytesPerRow * height;
    if (cost == 0) cost = 1;
    return cost;
}

- (UIImage *)imageFromData:(NSData *)data {
    CGFloat scale = [UIScreen mainScreen].scale;
    UIImage *image;
    YYImageDecoder *decoder = [YYImageDecoder decoderWithData:data scale:scale];
    image = [decoder frameAtIndex:0 decodeForDisplay:YES].image;
    return image;
}

#pragma mark - Initializer

+ (instancetype)sharedCache {
    static HJImageCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *cachePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                   NSUserDomainMask, YES) firstObject];
        cachePath = [cachePath stringByAppendingPathComponent:@"HJCache"];
        cachePath = [cachePath stringByAppendingPathComponent:@"Images"];
        cache = [[self alloc] initWithPath:cachePath];
    });
    return cache;
}

- (instancetype)init {
    @throw [NSException exceptionWithName:@"HJImageCache init error"
                                   reason:@"HJImageCache must be initialized with a path. Use 'initWithPath:' instead."
                                 userInfo:nil];
    return [self initWithPath:@""];
}

- (instancetype)initWithPath:(NSString *)path {
    HJMemoryCache *memoryCache = [HJMemoryCache new];
    memoryCache.shouldRemoveAllObjectsOnMemoryWarning = YES;
    memoryCache.shouldRemoveAllObjectsWhenEnteringBackground = YES;
    memoryCache.countLimit = NSUIntegerMax;
    memoryCache.costLimit = NSUIntegerMax;
    memoryCache.ageLimit = 12 * 60 * 60;
    
    HJDiskCache *diskCache = [[HJDiskCache alloc] initWithPath:path];
    diskCache.customArchiveBlock = ^(id object) { return (NSData *)object; };
    diskCache.customUnarchiveBlock = ^(NSData *data) { return (id)data; };
    diskCache.customFileNameBlock = ^NSString * _Nonnull(NSString * _Nonnull key) { return [self getFileNameForKey:key]; };
    if (!memoryCache || !diskCache) return nil;
    
    self = [super init];
    _memoryCache = memoryCache;
    _diskCache = diskCache;
    _path = [path copy];
    return self;
}

#pragma mark - Image Access Methods

- (void)setImage:(UIImage *)image forKey:(NSString *)key {
    [self setImage:image imageData:nil forKey:key withType:HJCachesTypeAll withBlock:nil];
}

- (void)setImage:(UIImage *)image imageData:(NSData *)imageData forKey:(NSString *)key withType:(HJCachesType)type withBlock:(nullable void(^)(void))block {
    if (!key || image == nil) return;
    
    __weak typeof(self) _self = self;
    if (type & HJCachesTypeMemory) { // add to memory cache
        dispatch_async(HJCacheImageCacheIOQueue(), ^{
            __strong typeof(_self) self = _self;
            if (!self) return;
            [self.memoryCache setObject:image forKey:key withCost:[self imageCost:image]];
        });
    }
    
    if (type & HJCachesTypeDisk) { // add to disk cache
        dispatch_async(HJCacheImageCacheIOQueue(), ^{
            __strong typeof(_self) self = _self;
            if (!self) return;
            NSData *data = [image yy_imageDataRepresentation];
            if (imageData.length) {
                [HJDiskCache setExtendedData:[NSKeyedArchiver archivedDataWithRootObject:imageData] toObject:data];
            }
            if (block) {
                [self.diskCache setObject:data forKey:key withBlock:block];
            } else {
                [self.diskCache setObject:data forKey:key];
            }
        });
    }
}

- (void)setImageWithPath:(nullable NSString *)path
               imageData:(nullable NSData *)imageData
                  forKey:(NSString *)key
                withType:(HJCachesType)type
               withBlock:(nullable void(^)(void))block {
    if (!key || !path) return;
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    [self setImage:image imageData:imageData forKey:key withType:type withBlock:block];
}

- (void)removeAllImages {
    [_memoryCache removeAllObjects];
    [_diskCache removeAllObjects];
}

- (void)removeImageForKey:(NSString *)key {
    [self removeImageForKey:key withType:HJCachesTypeAll];
}

- (void)removeImageForKey:(NSString *)key withType:(HJCachesType)type {
    if (type & HJCachesTypeMemory) [_memoryCache removeObjectForKey:key];
    if (type & HJCachesTypeDisk) [_diskCache removeObjectForKey:key];
}

- (BOOL)containsImageForKey:(NSString *)key {
    return [self containsImageForKey:key withType:HJCachesTypeAll];
}

- (BOOL)containsImageForKey:(NSString *)key withType:(HJCachesType)type {
    if (type & HJCachesTypeMemory) {
        if ([_memoryCache containsObjectForKey:key]) return YES;
    }
    if (type & HJCachesTypeDisk) {
        if ([_diskCache containsObjectForKey:key]) return YES;
    }
    return NO;
}

- (UIImage *)getImageForKey:(NSString *)key {
    return [self getImageForKey:key withType:HJCachesTypeAll];
}

- (UIImage *)getImageForKey:(NSString *)key withType:(HJCachesType)type {
    if (!key) return nil;
    
    if (type & HJCachesTypeMemory) {
        UIImage *image = [_memoryCache objectForKey:key];
        if (image) return image;
    }
    
    if (type & HJCachesTypeDisk) {
        NSData *data = (id)[_diskCache objectForKey:key];
        UIImage *image = [self imageFromData:data];
        if (image && (type & HJCachesTypeMemory)) {
            [_memoryCache setObject:image forKey:key withCost:[self imageCost:image]];
        }
        return image;
    }
    return nil;
}

- (void)getImageForKey:(NSString *)key withType:(HJCachesType)type withBlock:(void (^)(UIImage *image, HJCachesType type))block {
    if (!block) return;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *image = [self getImageForKey:key withType:type];
        dispatch_async(dispatch_get_main_queue(), ^{
            block(image, type);
        });
    });
}

- (NSData *)getImageDataForKey:(NSString *)key {
    if (!key) return nil;
    
    UIImage *object = [self getImageForKey:key];
    if (!object) return nil;
    
    id extendedData = nil;
    NSData *data = [HJDiskCache getExtendedDataFromObject:object];
    if (data) {
        extendedData = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    }
    
    return extendedData;
}

- (void)getImageDataForKey:(NSString *)key withBlock:(void (^)(NSData *imageData))block {
    if (!key || !block) return;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [self getImageDataForKey:key];
        dispatch_async(dispatch_get_main_queue(), ^{
            block(data);
        });
    });
}

- (NSString *)getPathForKey:(NSString *)key {
    if (!key) return nil;
    
    NSString *path = [NSString stringWithString:_path];
    path = [path stringByAppendingPathComponent:@"data"];
    return [path stringByAppendingPathComponent:[self getFileNameForKey:key]];
}

- (NSString *)getFileNameForKey:(NSString *)key {
    if (!key) return nil;
    
    return [NSString stringWithFormat:@"%@.jpg", key];
}

+ (unsigned long long)getFileSizeForKey:(NSString *)key {
    if (!key) return 0;
    NSString *path = [[HJImageCache sharedCache] getPathForKey:key];
    if (!path) return 0;
    
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    return [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
}

@end

