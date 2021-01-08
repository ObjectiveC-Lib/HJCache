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

// core
#import <HJCache/HJDiskCache.h>
#import <HJCache/HJMemoryCache.h>
#import <HJCache/HJCacheDefine.h>

// default
#import <HJCache/HJDefaultCache.h>
#import <HJCache/HJImageCache.h>
#import <HJCache/HJVideoCache.h>

#else  //__has_include("HJCache.h")

// core
#import "HJDiskCache.h"
#import "HJImageCache.h"
#import "HJCacheDefine.h"

// default
#import "HJDefaultCache.h"
#import "HJImageCache.h"
#import "HJVideoCache.h"

#endif
#endif /* HJCache_h */
