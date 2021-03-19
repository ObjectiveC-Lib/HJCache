//
//  HJCacheSDBridge.h
//  HJCache
//
//  Created by navy on 2021/3/19.
//

#ifndef HJCacheSDBridge_h
#define HJCacheSDBridge_h

#if __has_include(<HJCache/HJCacheSDBridge.h>)
#import <HJCache/HJDiskCache+SDAdditions.h>
#import <HJCache/HJMemoryCache+SDAdditions.h>
#import <HJCache/HJCommonCache+SDAdditions.h>
#elif __has_include("HJCacheSDBridge.h")
#import "HJDiskCache+SDAdditions.h"
#import "HJMemoryCache+SDAdditions.h"
#import "HJCommonCache+SDAdditions.h"
#endif

#endif /* HJCacheSDBridge_h */
