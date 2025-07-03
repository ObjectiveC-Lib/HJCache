//
//  HJKVStorage.h
//  HJCache
//
//  Created by navy on 2019/3/1.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, HJKVStorageType) {
    HJKVStorageTypeFile = 0,    // 数据存储在文件中，有文件名
    HJKVStorageTypeInline = 1,  // 数据直接存储在文件中，没有文件名
    HJKVStorageTypeMixed = 2,   // 混合模式，根据数据大小决定存储方式
};

@interface HJKVStorageItem : NSObject
@property (nonatomic, strong) NSString *key;
@property (nonatomic, strong) NSData *value;
@property (nonatomic, strong, nullable) NSString *filename;
@property (nonatomic) int size; // value's size in bytes
@property (nonatomic) int modTime;
@property (nonatomic) int accessTime;
@property (nonatomic, strong, nullable) NSData *extendedData;
@end


@interface HJKVStorage : NSObject

#pragma mark - Attribute

@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) HJKVStorageType type;
@property (nonatomic) BOOL errorLogsEnabled;

#pragma mark - Initializer

- (instancetype)init UNAVAILABLE_ATTRIBUTE;
+ (instancetype)new UNAVAILABLE_ATTRIBUTE;

- (nullable instancetype)initWithPath:(NSString *)path type:(HJKVStorageType)type NS_DESIGNATED_INITIALIZER;

#pragma mark - Save Items

- (BOOL)saveItem:(HJKVStorageItem *)item;
- (BOOL)saveItemWithKey:(NSString *)key value:(NSData *)value;
- (BOOL)saveItemWithKey:(NSString *)key value:(NSData *)value
               filename:(nullable NSString *)filename extendedData:(nullable NSData *)extendedData;

#pragma mark - Remove Items

- (BOOL)removeItemForKey:(NSString *)key;
- (BOOL)removeItemForKeys:(NSArray<NSString *> *)keys;
- (BOOL)removeItemsLargerThanSize:(int)size;
- (BOOL)removeitemsEarlierThanTime:(int)time;
- (BOOL)removeItemsToFitSize:(int)maxSize;
- (BOOL)removeItemsToFitCount:(int)maxCount;
- (BOOL)removeAllItems;
- (void)removeAllItemsWithProgressBlock:(nullable void(^)(int removeCount, int totalCount))progress
                               endBlock:(nullable void(^)(BOOL error))end;

#pragma mark - Get Items

- (nullable HJKVStorageItem *)getItemForKey:(NSString *)key;
- (nullable HJKVStorageItem *)getItemInfoForKey:(NSString *)key;
- (nullable NSData *)getItemValueForKey:(NSString *)key;
- (nullable NSArray<HJKVStorageItem *> *)getItemsForKeys:(NSArray<NSString *> *)keys;
- (nullable NSArray<HJKVStorageItem *> *)getItemInfoForKeys:(NSArray<NSString *> *)keys;
- (nullable NSDictionary<NSString *, NSData *> *)getItemValueForKeys:(NSArray<NSString *> *)keys;

#pragma mark - Get Storage Status

- (BOOL)itemExistForKey:(NSString *)key;
- (int)getItemsCount;
- (int)getItemsSize;

@end

NS_ASSUME_NONNULL_END
