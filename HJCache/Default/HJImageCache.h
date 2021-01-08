//
//  HJImageCache.h
//  HJCache
//
//  Created by navy on 2019/3/13.
//  Copyright © 2019 navy. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import "HJCache.h"

NS_ASSUME_NONNULL_BEGIN

@interface HJImageCache : NSObject

#pragma mark - Attribute

@property (copy, nullable) NSString *key;
@property (strong, readonly) HJMemoryCache *memoryCache;
@property (strong, readonly) HJDiskCache *diskCache;

#pragma mark - Initializer

- (instancetype)init UNAVAILABLE_ATTRIBUTE;
+ (instancetype)new UNAVAILABLE_ATTRIBUTE;
+ (instancetype)sharedCache;
- (nullable instancetype)initWithPath:(NSString *)path NS_DESIGNATED_INITIALIZER;

#pragma mark - Access Methods

- (void)setImage:(UIImage *)image forKey:(NSString *)key;
- (void)setImage:(nullable UIImage *)image
       imageData:(nullable NSData *)imageData
          forKey:(NSString *)key
        withType:(HJCachesType)type
       withBlock:(nullable void(^)(void))block;
- (void)setImageWithPath:(nullable NSString *)path
               imageData:(nullable NSData *)imageData
                  forKey:(NSString *)key
                withType:(HJCachesType)type
               withBlock:(nullable void(^)(void))block;

- (void)removeAllImages;
- (void)removeImageForKey:(NSString *)key;
- (void)removeImageForKey:(NSString *)key withType:(HJCachesType)type;

- (BOOL)containsImageForKey:(NSString *)key;
- (BOOL)containsImageForKey:(NSString *)key withType:(HJCachesType)type;

- (nullable UIImage *)getImageForKey:(NSString *)key;
- (nullable UIImage *)getImageForKey:(NSString *)key withType:(HJCachesType)type;
- (void)getImageForKey:(NSString *)key
              withType:(HJCachesType)type
             withBlock:(void(^)(UIImage * _Nullable image, HJCachesType type))block;

- (nullable NSData *)getImageDataForKey:(NSString *)key;
- (void)getImageDataForKey:(NSString *)key
                 withBlock:(void(^)(NSData * _Nullable imageData))block;

- (nullable NSString *)getPathForKey:(NSString *)key;
- (nullable NSString *)getFileNameForKey:(NSString *)key;
+ (unsigned long long)getFileSizeForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
