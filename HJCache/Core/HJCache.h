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
#import <HJCache/HJCommonCache.h>
#import <HJCache/HJCacheDefine.h>
#elif __has_include("HJCache.h")
#import "HJDiskCache.h"
#import "HJMemoryCache.h"
#import "HJCommonCache.h"
#import "HJCacheDefine.h"
#endif

#if __has_include(<HJCache/HJCacheDefault.h>)
#import <HJCache/HJCacheDefault.h>
#elif __has_include("HJCacheDefault.h")
#import "HJCacheDefault.h"
#endif

#if __has_include(<HJCache/HJCacheSDBridge.h>)
#import <HJCache/HJCacheSDBridge.h>
#elif __has_include("HJCacheSDBridge.h")
#import "HJCacheSDBridge.h"
#endif

#endif /* HJCache_h */
