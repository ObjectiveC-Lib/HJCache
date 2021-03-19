//
//  HJMemoryCache+SDAdditions.h
//  HJCache
//
//  Created by navy on 2021/3/19.
//

#import <HJCache/HJCache.h>
#import <SDWebImage/SDWebImage.h>

NS_ASSUME_NONNULL_BEGIN

/// This allow user who prefer HJMemoryCache to be used as SDWebImage's custom memory cache
@interface HJMemoryCache (SDAdditions) <SDMemoryCache>

@end

NS_ASSUME_NONNULL_END
