//
//  HJDiskCache+SDAdditions.m
//  HJCache
//
//  Created by navy on 2021/3/19.
//

#import "HJDiskCache+SDAdditions.h"
#import <objc/runtime.h>

@interface HJDiskCache ()
@property (nonatomic, strong, nullable) SDImageCacheConfig *sd_config;

- (NSString *)_filenameForKey:(NSString *)key;
@end


@implementation HJDiskCache (SDAdditions)

- (SDImageCacheConfig *)sd_config {
    return objc_getAssociatedObject(self, @selector(sd_config));
}

- (void)setSd_config:(SDImageCacheConfig *)sd_config {
    objc_setAssociatedObject(self, @selector(sd_config), sd_config, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - SDDiskCache

- (instancetype)initWithCachePath:(NSString *)cachePath config:(SDImageCacheConfig *)config {
    self = [self initWithPath:cachePath inlineThreshold:0];
    if (self) {
        self.sd_config = config;
    }
    return self;
}

- (BOOL)containsDataForKey:(NSString *)key {
    return [self containsObjectForKey:key];
}

- (NSData *)dataForKey:(NSString *)key {
    id<NSObject, NSCoding> object = (id<NSObject, NSCoding>)[self objectForKey:key];
    if ([object isKindOfClass:[NSData class]]) {
        return (NSData *)object;
    } else {
        return nil;
    }
}

- (void)setData:(NSData *)data forKey:(NSString *)key {
    if (!data) {
        return; // HJDiskCache will remove object if `data` is nil
    }
    
    [self setObject:data forKey:key];
}

- (NSData *)extendedDataForKey:(NSString *)key {
    id<NSObject, NSCoding> object = (id<NSObject, NSCoding>)[self objectForKey:key];
    return [self.class getExtendedDataFromObject:object];
}

- (void)setExtendedData:(NSData *)extendedData forKey:(NSString *)key {
    id<NSObject, NSCoding> object = (id<NSObject, NSCoding>)[self objectForKey:key];
    [self.class setExtendedData:nil toObject:object];
    [self setObject:object forKey:key];
}

- (void)removeDataForKey:(NSString *)key {
    [self removeObjectForKey:key];
}

- (void)removeAllData {
    [self removeAllObjects];
}

- (void)removeExpiredData {
    NSTimeInterval ageLimit = self.sd_config.maxDiskAge;
    NSUInteger sizeLimit = self.sd_config.maxDiskSize;
    
    [self trimToAge:ageLimit];
    [self trimToCost:sizeLimit];
}

- (NSString *)cachePathForKey:(NSString *)key {
    NSString *filename =  [self _filenameForKey:key];
    if (!filename) {
        return nil;
    }
    return [self.path stringByAppendingPathComponent:filename];
}

- (NSInteger)totalSize {
    return [self totalCost];
}

@end
