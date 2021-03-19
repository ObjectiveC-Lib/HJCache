//
//  HJCommonCache+SDAdditions.h
//  HJCache
//
//  Created by navy on 2021/3/19.
//

#import <HJCache/HJCache.h>
#import <SDWebImage/SDWebImage.h>


NS_ASSUME_NONNULL_BEGIN

/// This allow user who prefer HJCommonCache to be used as SDWebImage's custom image cache
@interface HJCommonCache (SDAdditions) <SDImageCache>

@end

NS_ASSUME_NONNULL_END
