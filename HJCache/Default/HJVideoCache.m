//
//  HJVideoCache.m
//  HJCache
//
//  Created by navy on 2019/3/18.
//  Copyright © 2019 navy. All rights reserved.
//

#import "HJVideoCache.h"
#import <Photos/Photos.h>
#import <AVFoundation/AVAssetImageGenerator.h>

static inline dispatch_queue_t HJCacheVideoCacheIOQueue() {
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
}

@interface HJVideoCache ()
@property (copy, nullable) NSString *path;
- (void)videoDataRepresentation:(PHAsset *)asset handler:(void (^)(NSData *data))handler;
- (void)videoDataRepresentation:(PHAsset *)video key:(NSString *)key handler:(void (^)(BOOL success))handler;
@end


@implementation HJVideoCache

- (void)videoDataRepresentation:(PHAsset *)asset handler:(void (^)(NSData *data))handler {
    if (!asset) return;
    
    [HJVideoCache getVideoWithAsset:asset progressHandler:nil completion:^(AVPlayerItem *playerItem, NSDictionary *info) {
        AVURLAsset *urlAsset = (AVURLAsset *)playerItem.asset;
        NSURL *url = urlAsset.URL;
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (handler) {
            handler(data);
        }
    }];
}

- (void)videoDataRepresentation:(PHAsset *)video key:(NSString *)key handler:(void (^)(BOOL success))handler {
    if (!video) return;
    
    NSString *path = [self getPathForKey:key];
    
    [HJVideoCache getVideoWithAsset:video progressHandler:nil completion:^(AVPlayerItem *playerItem, NSDictionary *info) {
        NSArray *export = [AVAssetExportSession exportPresetsCompatibleWithAsset:playerItem.asset];
        NSString *quality = AVAssetExportPresetMediumQuality;
        if ([export containsObject:quality]) {
            AVAssetExportSession *exportSession = [[AVAssetExportSession alloc]initWithAsset:playerItem.asset presetName:quality];
            exportSession.outputURL = [NSURL fileURLWithPath:path];
            exportSession.shouldOptimizeForNetworkUse = YES;
            exportSession.outputFileType = AVFileTypeMPEG4;
            [exportSession exportAsynchronouslyWithCompletionHandler:^{
                AVAssetExportSessionStatus status = [exportSession status];
                if (status == AVAssetExportSessionStatusCompleted) {
                    if (handler) {
                        handler(YES);
                    }
                } else if (status == AVAssetExportSessionStatusFailed) {
                    if (handler) {
                        handler(NO);
                    }
                }
            }];
        }
    }];
}

+ (void)getVideoWithAsset:(PHAsset *)asset
          progressHandler:(void (^)(double progress, NSError *error, BOOL *stop, NSDictionary *info))progressHandler
               completion:(void (^)(AVPlayerItem *playerItem, NSDictionary *info))completion {
    PHVideoRequestOptions *option = [[PHVideoRequestOptions alloc] init];
    option.networkAccessAllowed = YES;
    option.progressHandler = ^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (progressHandler) {
                progressHandler(progress, error, stop, info);
            }
        });
    };
    [[PHImageManager defaultManager] requestPlayerItemForVideo:asset
                                                       options:option
                                                 resultHandler:^(AVPlayerItem *playerItem, NSDictionary *info) {
        if (completion) completion(playerItem,info);
    }];
}

+ (UIImage *)getImageForVideo:(NSURL *)videoURL {
    if (!videoURL) return nil;
    
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:videoURL options:nil];
    if (!asset) return nil;
    
    AVAssetImageGenerator *assetImageGenerator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    assetImageGenerator.appliesPreferredTrackTransform = YES;
    assetImageGenerator.apertureMode = AVAssetImageGeneratorApertureModeEncodedPixels;
    
    CGImageRef imageRef = NULL;
    CFTimeInterval imageTime = 0;
    NSError *error = nil;
    imageRef = [assetImageGenerator copyCGImageAtTime:CMTimeMake(imageTime, 60) actualTime:NULL error:&error];
    
    UIImage *image = imageRef ? [[UIImage alloc] initWithCGImage:imageRef] : nil;
    return image;
}

+ (void)generateImageFromVideo:(NSURL *)url
                     completed:(void (^)(UIImage * _Nullable image, BOOL isSucc))completed {
    if (!url) {
        if (completed) {
            completed(nil, NO);
        }
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:url options:nil];
        if (asset.isExportable) {
            AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
            generator.appliesPreferredTrackTransform = YES;
            generator.apertureMode = AVAssetImageGeneratorApertureModeEncodedPixels;
            [generator generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:CMTimeMake(2, 1)]]
                                            completionHandler:^(CMTime requestedTime, CGImageRef  _Nullable image, CMTime actualTime, AVAssetImageGeneratorResult result, NSError * _Nullable error) {
                if (image && result == AVAssetImageGeneratorSucceeded) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completed) {
                            completed(nil, NO);
                        }
                    });
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completed) {
                            completed([[UIImage alloc] initWithCGImage:image], YES);
                        }
                    });
                }
            }];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completed) {
                    completed(nil, NO);
                }
            });
        }
    });
}

#pragma mark - Initializer

+ (instancetype)sharedCache {
    static HJVideoCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *cachePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                   NSUserDomainMask, YES) firstObject];
        cachePath = [cachePath stringByAppendingPathComponent:@"HJCache"];
        cachePath = [cachePath stringByAppendingPathComponent:@"Videos"];
        cache = [[self alloc] initWithPath:cachePath];
    });
    return cache;
}

- (instancetype)init {
    @throw [NSException exceptionWithName:@"HJVideoCache init error"
                                   reason:@"HJVideoCache must be initialized with a path. Use 'initWithPath:' instead."
                                 userInfo:nil];
    return [self initWithPath:@""];
}

- (instancetype)initWithPath:(NSString *)path {
    HJDiskCache *diskCache = [[HJDiskCache alloc] initWithPath:path];
    diskCache.customArchiveBlock = ^(id object) { return (NSData *)object; };
    diskCache.customUnarchiveBlock = ^(NSData *data) { return (id)data; };
    diskCache.customFileNameBlock = ^NSString * _Nonnull(NSString * _Nonnull key) { return [self getFileNameForKey:key]; };
    if (!diskCache) return nil;
    
    self = [super init];
    _diskCache = diskCache;
    _path = [path copy];
    return self;
}

#pragma mark - Access Methods

- (void)setVideo:(PHAsset *)video forKey:(NSString *)key {
    [self setVideo:video videoData:nil forKey:key withType:HJCachesTypeDisk withBlock:nil];
}

- (void)setVideo:(PHAsset *)video videoData:(NSData *)videoData forKey:(NSString *)key withType:(HJCachesType)type withBlock:(nullable void(^)(void))block {
    if (!key || video == nil) return;
    
    __weak typeof(self) _self = self;
    dispatch_async(HJCacheVideoCacheIOQueue(), ^{
        __strong typeof(_self) self = _self;
        if (!self) return;
        [self videoDataRepresentation:video key:key handler:^(BOOL success) {
            NSData *data = nil;
            if (success) {
                data = [NSData dataWithContentsOfFile:[self getPathForKey:key]];
                if (videoData.length) {
                    [HJDiskCache setExtendedData:[NSKeyedArchiver archivedDataWithRootObject:videoData] toObject:data];
                }
                if (block) {
                    [self.diskCache setObject:data forKey:key withBlock:block];
                } else {
                    [self.diskCache setObject:data forKey:key];
                }
            } else {
                [self videoDataRepresentation:video handler:^(NSData *data) {
                    if (videoData.length) {
                        [HJDiskCache setExtendedData:[NSKeyedArchiver archivedDataWithRootObject:videoData] toObject:data];
                    }
                    if (block) {
                        [self.diskCache setObject:data forKey:key withBlock:block];
                    } else {
                        [self.diskCache setObject:data forKey:key];
                    }
                }];
            }
        }];
    });
}

- (void)setVideoWithPath:(nullable NSString *)path
               videoData:(nullable NSData *)videoData
                  forKey:(NSString *)key
                withType:(HJCachesType)type
               withBlock:(nullable void(^)(void))block {
    if (!key || path == nil) return;
    
    __weak typeof(self) _self = self;
    dispatch_async(HJCacheVideoCacheIOQueue(), ^{
        __strong typeof(_self) self = _self;
        if (!self) return;
        PHFetchResult *fetchResult = [PHAsset fetchAssetsWithALAssetURLs:@[[NSURL fileURLWithPath:path]] options:nil];
        PHAsset *asset = fetchResult.firstObject;
        if(!asset) return;
        
        [self videoDataRepresentation:asset key:key handler:^(BOOL success) {
            if (success) {
                NSData *data = [NSData dataWithContentsOfFile:[self getPathForKey:key]];
                if (videoData.length) {
                    [HJDiskCache setExtendedData:[NSKeyedArchiver archivedDataWithRootObject:videoData] toObject:data];
                }
                if (block) {
                    [self.diskCache setObject:data forKey:key withBlock:block];
                } else {
                    [self.diskCache setObject:data forKey:key];
                }
            }
        }];
    });
}

- (void)removeAllVideos {
    [_diskCache removeAllObjects];
}

- (void)removeVideoForKey:(NSString *)key {
    [_diskCache removeObjectForKey:key];
}

- (BOOL)containsVideoForKey:(NSString *)key {
    if ([_diskCache containsObjectForKey:key]) return YES;
    return NO;
}

- (NSData *)getVideoForKey:(NSString *)key {
    if (!key) return nil;
    return (NSData *)[_diskCache objectForKey:key];
}

- (void)getVideoForKey:(NSString *)key withBlock:(void(^)(NSData * _Nullable video, HJCachesType type))block {
    if (!block) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *video = nil;
        video = (NSData *)[self->_diskCache objectForKey:key];
        if (video) {
            dispatch_async(dispatch_get_main_queue(), ^{
                block(video, HJCachesTypeDisk);
            });
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            block(nil, HJCachesTypeDisk);
        });
    });
}

- (NSData *)getVideoDataForKey:(NSString *)key {
    if (!key) return nil;
    
    NSData *object = [self getVideoForKey:key];
    if (!object) return nil;
    
    id extendedData = nil;
    NSData *data = [HJDiskCache getExtendedDataFromObject:object];
    if (data) {
        extendedData = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    }
    
    return extendedData;
}

- (void)getVideoDataForKey:(NSString *)key withBlock:(void (^)(NSData *videoData))block {
    if (!key || !block) return;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [self getVideoDataForKey:key];
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
    
    return [NSString stringWithFormat:@"%@.mp4", key];
}

+ (unsigned long long)getFileSizeForKey:(NSString *)key {
    if (!key) return 0;
    NSString *path = [[HJVideoCache sharedCache] getPathForKey:key];
    if (!path) return 0;
    
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    return [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
}

@end
