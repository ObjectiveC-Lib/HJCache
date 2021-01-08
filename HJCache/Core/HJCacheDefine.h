//
//  HJCacheDefine.h
//  HJCache
//
//  Created by navy on 2021/1/8.
//

#ifndef HJCacheDefine_h
#define HJCacheDefine_h

typedef NS_OPTIONS(NSUInteger, HJCachesType) {
    HJCachesTypeMemory  = 1 << 1,
    HJCachesTypeDisk    = 1 << 2,
    HJCachesTypeAll     = HJCachesTypeMemory | HJCachesTypeDisk,
};

#endif /* HJCacheDefine_h */
