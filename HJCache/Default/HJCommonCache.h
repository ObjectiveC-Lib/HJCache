//
//  HJCommonCache.h
//  HJCache
//
//  Created by navy on 2019/3/6.
//

#import <Foundation/Foundation.h>

@class HJMemoryCache, HJDiskCache;

NS_ASSUME_NONNULL_BEGIN

@interface HJCommonCache : NSObject

#pragma mark - Attribute

@property (strong, readonly) HJMemoryCache *memoryCache;
@property (strong, readonly) HJDiskCache *diskCache;

#pragma mark - Initializer

+ (instancetype)new UNAVAILABLE_ATTRIBUTE;
- (instancetype)init UNAVAILABLE_ATTRIBUTE;
- (nullable instancetype)initWithPath:(NSString *)path NS_DESIGNATED_INITIALIZER;
+ (instancetype)sharedCache;

#pragma mark - Access Methods

- (BOOL)containsObjectForKey:(NSString *)key;
- (void)containsObjectForKey:(NSString *)key withBlock:(nullable void(^)(NSString *key, BOOL contains))block;

- (nullable id<NSCoding>)objectForKey:(NSString *)key;
- (void)objectForKey:(NSString *)key withBlock:(nullable void(^)(NSString *key, id<NSCoding> object))block;

- (void)setObject:(nullable id<NSCoding>)object forKey:(NSString *)key;
- (void)setObject:(nullable id<NSCoding>)object forKey:(NSString *)key withBlock:(nullable void(^)(void))block;

- (void)removeObjectForKey:(NSString *)key;
- (void)removeObjectForKey:(NSString *)key withBlock:(nullable void(^)(NSString *key))block;

- (void)removeAllObjects;
- (void)removeAllObjectsWithBlock:(void(^)(void))block;

- (void)removeAllObjectsWithProgressBlock:(nullable void(^)(int removedCount, int totalCount))progress
                                 endBlock:(nullable void(^)(BOOL error))end;

@end

NS_ASSUME_NONNULL_END
