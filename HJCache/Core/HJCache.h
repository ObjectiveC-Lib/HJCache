//
//  HJCache.h
//  HJCache
//
//  Created by navy on 2021/1/8.
//

#ifndef HJCache_h
#define HJCache_h

//! Project version number for HJCache.
FOUNDATION_EXPORT double HJCacheVersionNumber;
//! Project version string for HJCache.
FOUNDATION_EXPORT const unsigned char HJCacheVersionString[];

#if __has_include(<HJCache/HJCache.h>)
#import <HJCache/HJDiskCache.h>
#import <HJCache/HJMemoryCache.h>
#import <HJCache/HJCacheDefine.h>
#elif __has_include("HJCache.h")
#import "HJDiskCache.h"
#import "HJImageCache.h"
#import "HJCacheDefine.h"
#endif

#if __has_include(<HJCache/HJCacheDefault.h>)
#elif __has_include("HJCacheDefault.h")
#import "HJCacheDefault.h"
#endif

#endif /* HJCache_h */
