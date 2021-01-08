//
//  HJVideoCache.h
//  HJUpload
//
//  Created by navy on 2019/3/18.
//  Copyright © 2019 navy. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import "HJCache.h"

NS_ASSUME_NONNULL_BEGIN

@interface HJVideoCache : NSObject

#pragma mark - Attribute

@property (copy, nullable) NSString *key;
@property (strong, readonly) HJDiskCache *diskCache;

#pragma mark - Initializer

- (instancetype)init UNAVAILABLE_ATTRIBUTE;
+ (instancetype)new UNAVAILABLE_ATTRIBUTE;
+ (instancetype)sharedCache;
- (nullable instancetype)initWithPath:(NSString *)path NS_DESIGNATED_INITIALIZER;

#pragma mark - Video Access Methods

- (void)setVideo:(PHAsset *)video forKey:(NSString *)key;
- (void)setVideo:(nullable PHAsset *)video
       videoData:(nullable NSData *)videoData
          forKey:(NSString *)key
        withType:(HJCachesType)type
       withBlock:(nullable void(^)(void))block;
- (void)setVideoWithPath:(nullable NSString *)path
               videoData:(nullable NSData *)videoData
                  forKey:(NSString *)key
                withType:(HJCachesType)type
               withBlock:(nullable void(^)(void))block;

- (void)removeAllVideos;
- (void)removeVideoForKey:(NSString *)key;

- (BOOL)containsVideoForKey:(NSString *)key;

- (NSData *)getVideoForKey:(NSString *)key;
- (void)getVideoForKey:(NSString *)key withBlock:(void(^)(NSData * _Nullable video, HJCachesType type))block;

- (nullable NSData *)getVideoDataForKey:(NSString *)key;
- (void)getVideoDataForKey:(NSString *)key
                 withBlock:(void(^)(NSData * _Nullable imageData))block;

- (nullable NSString *)getPathForKey:(NSString *)key;
- (nullable NSString *)getFileNameForKey:(NSString *)key;
+ (unsigned long long)getFileSizeForKey:(NSString *)key;

+ (UIImage *)getImageForVideo:(NSURL *)videoURL;
+ (void)generateImageFromVideo:(NSURL *)url
                     completed:(void (^)(UIImage * _Nullable image, BOOL isSucc))completed;
@end

NS_ASSUME_NONNULL_END
