//
//  HJCacheDefault.h
//  HJCache
//
//  Created by navy on 2021/1/8.
//

#ifndef HJCacheDefault_h
#define HJCacheDefault_h

#if __has_include(<HJCache/HJCacheDefault.h>)
#import <HJCache/HJImageCache.h>
#import <HJCache/HJVideoCache.h>
#elif __has_include("HJCacheDefault.h")
#import "HJImageCache.h"
#import "HJVideoCache.h"
#endif

#endif /* HJCacheDefault_h */
