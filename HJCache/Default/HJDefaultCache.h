//
//  HJDefaultCache.h
//  HJCache
//
//  Created by navy on 2021/1/8.
//

#ifndef HJDefaultCache_h
#define HJDefaultCache_h

#if __has_include(<HJCache/HJDefaultCache.h>)
#import <HJCache/HJCommonCache.h>
#import <HJCache/HJImageCache.h>
#import <HJCache/HJVideoCache.h>
#elif __has_include("HJDefaultCache.h")
#import "HJCommonCache.h"
#import "HJImageCache.h"
#import "HJVideoCache.h"
#endif

#endif /* HJDefaultCache_h */
