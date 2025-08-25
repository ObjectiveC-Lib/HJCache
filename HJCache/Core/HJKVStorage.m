//
//  HJKVStorage.m
//  HJCache
//
//  Created by navy on 2019/3/1.
//

#import "HJKVStorage.h"
#import <UIKit/UIKit.h>
#import <time.h>

static const NSUInteger kMaxErrorRetryCount = 0;
static const NSTimeInterval kMinRetryTimeInterval = 2.0;
static const int kPathLengthMax = PATH_MAX - 64;

static NSString *const kDataDirectoryName = @"data";
static NSString *const kTrashDirectoryName = @"trash";
static NSString *const kManifestFileName = @"manifest.plist";

// 添加文件名生成函数
static inline NSString *HJSanitizeFileNameString(NSString * _Nullable fileName) {
    if ([fileName length] == 0) {
        return fileName;
    }
    // note: `:` is the only invalid char on Apple file system
    // but `/` or `\` is valid
    // \0 is also special case (which cause Foundation API treat the C string as EOF)
    NSCharacterSet* illegalFileNameCharacters = [NSCharacterSet characterSetWithCharactersInString:@"\0:"];
    return [[fileName componentsSeparatedByCharactersInSet:illegalFileNameCharacters] componentsJoinedByString:@""];
}

static inline NSString * _Nonnull HJFileNameForKey(NSString * _Nullable key) {
    if (key.length == 0) {
        return @"";
    }
    
    // 使用 MD5 哈希生成文件名
    const char *str = key.UTF8String;
    if (str == NULL) {
        str = "";
    }
    
    // 简单的哈希算法，避免依赖 CommonCrypto
    unsigned long hash = 5381;
    int c;
    while ((c = *str++)) {
        hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
    }
    
    NSString *ext = key.pathExtension;
    ext = HJSanitizeFileNameString(ext);
    
    NSString *filename = [NSString stringWithFormat:@"%lx%@",
                          hash, ext.length == 0 ? @"" : [NSString stringWithFormat:@".%@", ext]];
    return filename;
}

/// Returns nil in App Extension.
static UIApplication *_HJSharedApplication(void) {
    static BOOL isAppExtension = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"UIApplication");
        if (!cls || ![cls respondsToSelector:@selector(sharedApplication)]) isAppExtension = YES;
        if ([[[NSBundle mainBundle] bundlePath] hasSuffix:@".appex"]) isAppExtension = YES;
    });
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    return isAppExtension ? nil : [UIApplication performSelector:@selector(sharedApplication)];
#pragma clang diagnostic pop
}

@implementation HJKVStorageItem
@end

@implementation HJKVStorage {
    NSString *_path;
    NSString *_dataPath;
    NSString *_trashPath;
    NSString *_manifestPath;
    
    // 添加 NSFileManager 和 manifest 字典
    NSFileManager *_fileManager;
    NSMutableDictionary *_manifest;
    dispatch_queue_t _manifestQueue;
    dispatch_queue_t _trashQueue;
}

#pragma mark - Manifest Management

- (BOOL)_loadManifest {
    if (!_manifestPath) return NO;
    
    NSData *data = [NSData dataWithContentsOfFile:_manifestPath];
    if (data) {
        NSDictionary *dict = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil];
        if ([dict isKindOfClass:[NSDictionary class]]) {
            // 深度复制确保所有嵌套对象都是可变的
            _manifest = [self _deepMutableCopy:dict];
            return YES;
        }
    }
    
    _manifest = [NSMutableDictionary new];
    return YES;
}

// 深度可变复制方法
- (NSMutableDictionary *)_deepMutableCopy:(NSDictionary *)dict {
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionaryWithCapacity:dict.count];
    
    for (NSString *key in dict.allKeys) {
        id value = dict[key];
        if ([value isKindOfClass:[NSDictionary class]]) {
            // 递归处理嵌套字典
            mutableDict[key] = [self _deepMutableCopy:value];
        } else {
            // 其他类型直接赋值
            mutableDict[key] = value;
        }
    }
    
    return mutableDict;
}

- (BOOL)_saveManifest {
    if (!_manifestPath || !_manifest) return NO;
    
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:_manifest format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    return [data writeToFile:_manifestPath atomically:YES];
}

- (NSString *)_filePathForKey:(NSString *)key {
    if (key.length == 0) return nil;
    NSString *filename = HJFileNameForKey(key);
    return [_dataPath stringByAppendingPathComponent:filename];
}

- (NSString *)_extendedDataPathForKey:(NSString *)key {
    if (key.length == 0) return nil;
    NSString *filename = [HJFileNameForKey(key) stringByAppendingString:@".ext"];
    return [_dataPath stringByAppendingPathComponent:filename];
}

#pragma mark - File Operations

- (BOOL)_fileWriteWithName:(NSString *)filename data:(NSData *)data {
    NSString *path = [_dataPath stringByAppendingPathComponent:filename];
    return [data writeToFile:path atomically:NO];
}

- (NSData *)_fileReadWithName:(NSString *)filename {
    NSString *path = [_dataPath stringByAppendingPathComponent:filename];
    NSData *data = [NSData dataWithContentsOfFile:path];
    return data;
}

- (BOOL)_fileDeleteWithName:(NSString *)filename {
    NSString *path = [_dataPath stringByAppendingPathComponent:filename];
    return [_fileManager removeItemAtPath:path error:NULL];
}

- (BOOL)_fileMoveAllToTrash {
    CFUUIDRef uuidRef = CFUUIDCreate(NULL);
    CFStringRef uuid = CFUUIDCreateString(NULL, uuidRef);
    CFRelease(uuidRef);
    NSString *tmpPath = [_trashPath stringByAppendingPathComponent:(__bridge NSString *)(uuid)];
    BOOL suc = [_fileManager moveItemAtPath:_dataPath toPath:tmpPath error:nil];
    if (suc) {
        suc = [_fileManager createDirectoryAtPath:_dataPath withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    CFRelease(uuid);
    return suc;
}

- (void)_fileEmptyTrashInBackground {
    NSString *trashPath = _trashPath;
    dispatch_queue_t queue = _trashQueue;
    dispatch_async(queue, ^{
        NSFileManager *manager = [NSFileManager new];
        NSArray *directoryContents = [manager contentsOfDirectoryAtPath:trashPath error:NULL];
        for (NSString *path in directoryContents) {
            NSString *fullPath = [trashPath stringByAppendingPathComponent:path];
            [manager removeItemAtPath:fullPath error:NULL];
        }
    });
}

#pragma mark - Manifest Operations

- (BOOL)_manifestSaveWithKey:(NSString *)key value:(NSData *)value fileName:(NSString *)fileName extendedData:(NSData *)extendedData {
    if (!_manifest) return NO;
    
    int timestamp = (int)time(NULL);
    NSMutableDictionary *itemInfo = [NSMutableDictionary new];
    itemInfo[@"filename"] = fileName ?: @"";
    itemInfo[@"size"] = @(value.length);
    itemInfo[@"modification_time"] = @(timestamp);
    itemInfo[@"last_access_time"] = @(timestamp);
    
    _manifest[key] = itemInfo;
    
    // 保存扩展数据到单独文件
    if (extendedData) {
        NSString *extendedDataPath = [self _extendedDataPathForKey:key];
        [extendedData writeToFile:extendedDataPath atomically:YES];
    }
    
    return [self _saveManifest];
}

- (BOOL)_manifestUpdateAccessTimeWithKey:(NSString *)key {
    if (!_manifest) return NO;
    
    NSMutableDictionary *itemInfo = _manifest[key];
    if (itemInfo) {
        itemInfo[@"last_access_time"] = @((int)time(NULL));
        return [self _saveManifest];
    }
    return NO;
}

- (BOOL)_manifestDeleteItemWithKey:(NSString *)key {
    if (!_manifest) return NO;
    
    [_manifest removeObjectForKey:key];
    
    // 删除扩展数据文件
    NSString *extendedDataPath = [self _extendedDataPathForKey:key];
    [_fileManager removeItemAtPath:extendedDataPath error:NULL];
    
    return [self _saveManifest];
}

- (BOOL)_manifestDeleteItemWithKeys:(NSArray *)keys {
    if (!_manifest) return NO;
    
    for (NSString *key in keys) {
        [_manifest removeObjectForKey:key];
        
        // 删除扩展数据文件
        NSString *extendedDataPath = [self _extendedDataPathForKey:key];
        [_fileManager removeItemAtPath:extendedDataPath error:NULL];
    }
    
    return [self _saveManifest];
}

- (HJKVStorageItem *)_manifestGetItemWithKey:(NSString *)key excludeInlineData:(BOOL)excludeInlineData {
    if (!_manifest) return nil;
    
    NSDictionary *itemInfo = _manifest[key];
    if (!itemInfo) return nil;
    
    HJKVStorageItem *item = [HJKVStorageItem new];
    item.key = key;
    item.filename = itemInfo[@"filename"];
    item.size = [itemInfo[@"size"] intValue];
    item.modTime = [itemInfo[@"modification_time"] intValue];
    item.accessTime = [itemInfo[@"last_access_time"] intValue];
    
    // 读取扩展数据
    NSString *extendedDataPath = [self _extendedDataPathForKey:key];
    if ([_fileManager fileExistsAtPath:extendedDataPath]) {
        item.extendedData = [NSData dataWithContentsOfFile:extendedDataPath];
    }
    
    // 读取数据值
    if (!excludeInlineData) {
        if (item.filename.length > 0) {
            item.value = [self _fileReadWithName:item.filename];
        } else {
            // 如果没有文件名，数据直接存储在文件中
            NSString *filePath = [self _filePathForKey:key];
            item.value = [NSData dataWithContentsOfFile:filePath];
        }
    }
    
    return item;
}

- (NSMutableArray *)_manifestGetItemWithKeys:(NSArray *)keys excludeInlineData:(BOOL)excludeInlineData {
    if (!_manifest) return nil;
    
    NSMutableArray *items = [NSMutableArray new];
    for (NSString *key in keys) {
        HJKVStorageItem *item = [self _manifestGetItemWithKey:key excludeInlineData:excludeInlineData];
        if (item) {
            [items addObject:item];
        }
    }
    return items;
}

- (NSData *)_manifestGetValueWithKey:(NSString *)key {
    if (!_manifest) return nil;
    
    NSDictionary *itemInfo = _manifest[key];
    if (!itemInfo) return nil;
    
    NSString *filename = itemInfo[@"filename"];
    if (filename.length > 0) {
        return [self _fileReadWithName:filename];
    } else {
        // 如果没有文件名，数据直接存储在文件中
        NSString *filePath = [self _filePathForKey:key];
        return [NSData dataWithContentsOfFile:filePath];
    }
}

- (NSString *)_manifestGetFilenameWithKey:(NSString *)key {
    if (!_manifest) return nil;
    
    NSDictionary *itemInfo = _manifest[key];
    return itemInfo[@"filename"];
}

- (NSMutableArray *)_manifestGetFilenamesWithKeys:(NSArray *)keys {
    if (!_manifest) return nil;
    
    NSMutableArray *filenames = [NSMutableArray new];
    for (NSString *key in keys) {
        NSString *filename = [self _manifestGetFilenameWithKey:key];
        if (filename.length > 0) {
            [filenames addObject:filename];
        }
    }
    return filenames;
}

- (NSMutableArray *)_manifestGetFilenamesWithSizeLargerThan:(int)size {
    if (!_manifest) return nil;
    
    NSMutableArray *filenames = [NSMutableArray new];
    for (NSString *key in _manifest.allKeys) {
        NSDictionary *itemInfo = _manifest[key];
        int itemSize = [itemInfo[@"size"] intValue];
        if (itemSize > size) {
            NSString *filename = itemInfo[@"filename"];
            if (filename.length > 0) {
                [filenames addObject:filename];
            }
        }
    }
    return filenames;
}

- (NSMutableArray *)_manifestGetFilenamesWithTimeEarlierThan:(int)time {
    if (!_manifest) return nil;
    
    NSMutableArray *filenames = [NSMutableArray new];
    for (NSString *key in _manifest.allKeys) {
        NSDictionary *itemInfo = _manifest[key];
        int accessTime = [itemInfo[@"last_access_time"] intValue];
        if (accessTime < time) {
            NSString *filename = itemInfo[@"filename"];
            if (filename.length > 0) {
                [filenames addObject:filename];
            }
        }
    }
    return filenames;
}

- (NSMutableArray *)_manifestGetItemSizeInfoOrderByTimeAscWithLimit:(int)count {
    if (!_manifest) return nil;
    
    // 按访问时间排序
    NSArray *sortedKeys = [_manifest.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *key1, NSString *key2) {
        NSDictionary *info1 = _manifest[key1];
        NSDictionary *info2 = _manifest[key2];
        int time1 = [info1[@"last_access_time"] intValue];
        int time2 = [info2[@"last_access_time"] intValue];
        return time1 - time2;
    }];
    
    NSMutableArray *items = [NSMutableArray new];
    int limit = MIN(count, (int)sortedKeys.count);
    for (int i = 0; i < limit; i++) {
        NSString *key = sortedKeys[i];
        NSDictionary *itemInfo = _manifest[key];
        
        HJKVStorageItem *item = [HJKVStorageItem new];
        item.key = key;
        item.filename = itemInfo[@"filename"];
        item.size = [itemInfo[@"size"] intValue];
        [items addObject:item];
    }
    return items;
}

- (int)_manifestGetItemCountWithKey:(NSString *)key {
    if (!_manifest) return 0;
    return _manifest[key] ? 1 : 0;
}

- (int)_manifestGetTotalItemSize {
    if (!_manifest) return 0;
    
    int totalSize = 0;
    for (NSDictionary *itemInfo in _manifest.allValues) {
        totalSize += [itemInfo[@"size"] intValue];
    }
    return totalSize;
}

- (int)_manifestGetTotalItemCount {
    if (!_manifest) return 0;
    return (int)_manifest.count;
}

#pragma mark - Private

- (void)_reset {
    // 删除 manifest 文件
    [_fileManager removeItemAtPath:_manifestPath error:nil];
    
    [self _fileMoveAllToTrash];
    [self _fileEmptyTrashInBackground];
    
    // 重新初始化 manifest
    _manifest = [NSMutableDictionary new];
    [self _saveManifest];
}

#pragma mark - Initializer

- (void)dealloc {
    UIBackgroundTaskIdentifier taskID = [_HJSharedApplication() beginBackgroundTaskWithExpirationHandler:^{}];
    if (taskID != UIBackgroundTaskInvalid) {
        [_HJSharedApplication() endBackgroundTask:taskID];
    }
}

- (instancetype)init {
    @throw [NSException exceptionWithName:@"HJKVStorage init error"
                                   reason:@"Please use the designated initializer and pass the 'path' and 'type'."
                                 userInfo:nil];
    return [self initWithPath:@"" type:HJKVStorageTypeFile];
}

- (nullable instancetype)initWithPath:(NSString *)path type:(HJKVStorageType)type {
    if (path.length == 0 || path.length > kPathLengthMax) {
        NSLog(@"HJKVStorage init error: invalid path: [%@].", path);
        return nil;
    }
    if (type > HJKVStorageTypeMixed) {
        NSLog(@"HJKVStorage init error: invalid type: %lu.", (unsigned long)type);
        return nil;
    }
    
    self = [super init];
    _path = path.copy;
    _type = type;
    _dataPath = [path stringByAppendingPathComponent:kDataDirectoryName];
    _trashPath = [path stringByAppendingPathComponent:kTrashDirectoryName];
    _manifestPath = [path stringByAppendingPathComponent:kManifestFileName];
    _trashQueue = dispatch_queue_create("com.hj.cache.disk.trash", DISPATCH_QUEUE_SERIAL);
    _manifestQueue = dispatch_queue_create("com.hj.cache.disk.manifest", DISPATCH_QUEUE_SERIAL);
    _fileManager = [NSFileManager new];
    _errorLogsEnabled = YES;
    
    NSError *error = nil;
    if (![_fileManager createDirectoryAtPath:path
                 withIntermediateDirectories:YES
                                  attributes:nil
                                       error:&error] ||
        ![_fileManager createDirectoryAtPath:[path stringByAppendingPathComponent:kDataDirectoryName]
                 withIntermediateDirectories:YES
                                  attributes:nil
                                       error:&error] ||
        ![_fileManager createDirectoryAtPath:[path stringByAppendingPathComponent:kTrashDirectoryName]
                 withIntermediateDirectories:YES
                                  attributes:nil
                                       error:&error]) {
        NSLog(@"HJKVStorage init error:%@", error);
        return nil;
    }
    
    // 初始化 manifest
    if (![self _loadManifest]) {
        [self _reset];
        if (![self _loadManifest]) {
            NSLog(@"HJKVStorage init error: fail to load manifest.");
            return nil;
        }
    }
    
    [self _fileEmptyTrashInBackground];
    return self;
}

#pragma mark - Save Items

- (BOOL)saveItem:(HJKVStorageItem *)item {
    return [self saveItemWithKey:item.key value:item.value
                        filename:item.filename extendedData:item.extendedData];
}

- (BOOL)saveItemWithKey:(NSString *)key value:(NSData *)value {
    return [self saveItemWithKey:key value:value filename:nil extendedData:nil];
}

- (BOOL)saveItemWithKey:(NSString *)key
                  value:(NSData *)value
               filename:(nullable NSString *)filename
           extendedData:(nullable NSData *)extendedData {
    if (key.length == 0 || value.length == 0) return NO;
    if (_type == HJKVStorageTypeFile && filename.length == 0) return NO;
    
    if (filename.length) {
        if (![self _fileWriteWithName:filename data:value]) return NO;
        if (![self _manifestSaveWithKey:key value:value fileName:filename extendedData:extendedData]) {
            [self _fileDeleteWithName:filename];
            return NO;
        }
        return YES;
    } else {
        if (_type != HJKVStorageTypeInline) {
            NSString *filename = [self _manifestGetFilenameWithKey:key];
            if (filename.length) [self _fileDeleteWithName:filename];
        }
        
        // 直接保存到文件
        NSString *filePath = [self _filePathForKey:key];
        if (![value writeToFile:filePath atomically:YES]) return NO;
        
        return [self _manifestSaveWithKey:key value:value fileName:nil extendedData:extendedData];
    }
}

#pragma mark - Remove Items

- (BOOL)removeItemForKey:(NSString *)key {
    if (key.length == 0) return NO;
    switch (_type) {
        case HJKVStorageTypeInline: {
            return [self _manifestDeleteItemWithKey:key];
        } break;
        case HJKVStorageTypeFile:
        case HJKVStorageTypeMixed: {
            NSString *filename = [self _manifestGetFilenameWithKey:key];
            if (filename.length) {
                [self _fileDeleteWithName:filename];
            } else {
                // 删除直接存储的文件
                NSString *filePath = [self _filePathForKey:key];
                [_fileManager removeItemAtPath:filePath error:NULL];
            }
            return [self _manifestDeleteItemWithKey:key];
        } break;
        default: return NO;
    }
}

- (BOOL)removeItemForKeys:(NSArray<NSString *> *)keys {
    if (keys.count == 0) return NO;
    
    switch (_type) {
        case HJKVStorageTypeInline: {
            return [self _manifestDeleteItemWithKeys:keys];
        } break;
        case HJKVStorageTypeFile:
        case HJKVStorageTypeMixed: {
            NSArray *filenames = [self _manifestGetFilenamesWithKeys:keys];
            for (NSString *filename in filenames) {
                [self _fileDeleteWithName:filename];
            }
            
            // 删除直接存储的文件
            for (NSString *key in keys) {
                NSString *filePath = [self _filePathForKey:key];
                [_fileManager removeItemAtPath:filePath error:NULL];
            }
            
            return [self _manifestDeleteItemWithKeys:keys];
        } break;
        default: return NO;
    }
}

- (BOOL)removeItemsLargerThanSize:(int)size  {
    if (size == INT_MAX) return YES;
    if (size <= 0) return [self removeAllItems];
    
    switch (_type) {
        case HJKVStorageTypeInline: {
            // 获取需要删除的键
            NSMutableArray *keysToDelete = [NSMutableArray new];
            for (NSString *key in _manifest.allKeys) {
                NSDictionary *itemInfo = _manifest[key];
                int itemSize = [itemInfo[@"size"] intValue];
                if (itemSize > size) {
                    [keysToDelete addObject:key];
                }
            }
            return [self removeItemForKeys:keysToDelete];
        } break;
        case HJKVStorageTypeFile:
        case HJKVStorageTypeMixed: {
            NSArray *filenames = [self _manifestGetFilenamesWithSizeLargerThan:size];
            for (NSString *name in filenames) {
                [self _fileDeleteWithName:name];
            }
            
            // 获取需要删除的键
            NSMutableArray *keysToDelete = [NSMutableArray new];
            for (NSString *key in _manifest.allKeys) {
                NSDictionary *itemInfo = _manifest[key];
                int itemSize = [itemInfo[@"size"] intValue];
                if (itemSize > size) {
                    [keysToDelete addObject:key];
                }
            }
            return [self removeItemForKeys:keysToDelete];
        } break;
    }
    return NO;
}

- (BOOL)removeitemsEarlierThanTime:(int)time {
    if (time <= 0) return YES;
    if (time == INT_MAX) return [self removeAllItems];
    
    switch (_type) {
        case HJKVStorageTypeInline: {
            // 获取需要删除的键
            NSMutableArray *keysToDelete = [NSMutableArray new];
            for (NSString *key in _manifest.allKeys) {
                NSDictionary *itemInfo = _manifest[key];
                int accessTime = [itemInfo[@"last_access_time"] intValue];
                if (accessTime < time) {
                    [keysToDelete addObject:key];
                }
            }
            return [self removeItemForKeys:keysToDelete];
        } break;
        case HJKVStorageTypeFile:
        case HJKVStorageTypeMixed: {
            NSArray *filenames = [self _manifestGetFilenamesWithTimeEarlierThan:time];
            for (NSString *name in filenames) {
                [self _fileDeleteWithName:name];
            }
            
            // 获取需要删除的键
            NSMutableArray *keysToDelete = [NSMutableArray new];
            for (NSString *key in _manifest.allKeys) {
                NSDictionary *itemInfo = _manifest[key];
                int accessTime = [itemInfo[@"last_access_time"] intValue];
                if (accessTime < time) {
                    [keysToDelete addObject:key];
                }
            }
            return [self removeItemForKeys:keysToDelete];
        } break;
    }
    
    return NO;
}

- (BOOL)removeItemsToFitSize:(int)maxSize  {
    if (maxSize == INT_MAX) return YES;
    if (maxSize <= 0) return [self removeAllItems];
    
    int total = [self _manifestGetTotalItemSize];
    if (total < 0) return NO;
    if (total <= maxSize) return YES;
    
    NSArray *items = nil;
    BOOL suc = NO;
    do {
        int perCount = 16;
        items = [self _manifestGetItemSizeInfoOrderByTimeAscWithLimit:perCount];
        for (HJKVStorageItem *item in items) {
            if (total > maxSize) {
                if (item.filename.length) {
                    [self _fileDeleteWithName:item.filename];
                } else {
                    // 删除直接存储的文件
                    NSString *filePath = [self _filePathForKey:item.key];
                    [_fileManager removeItemAtPath:filePath error:NULL];
                }
                suc = [self _manifestDeleteItemWithKey:item.key];
                total -= item.size;
            } else {
                break;
            }
            if (!suc) break;
        }
    } while (total > maxSize && items.count > 0 && suc);
    return suc;
}

- (BOOL)removeItemsToFitCount:(int)maxCount {
    if (maxCount == INT_MAX) return YES;
    if (maxCount <= 0) return [self removeAllItems];
    
    int total = [self _manifestGetTotalItemCount];
    if (total < 0) return NO;
    if (total <= maxCount) return YES;
    
    NSArray *items = nil;
    BOOL suc = NO;
    do {
        int perCount = 16;
        items = [self _manifestGetItemSizeInfoOrderByTimeAscWithLimit:perCount];
        for (HJKVStorageItem *item in items) {
            if (total > maxCount) {
                if (item.filename.length) {
                    [self _fileDeleteWithName:item.filename];
                } else {
                    // 删除直接存储的文件
                    NSString *filePath = [self _filePathForKey:item.key];
                    [_fileManager removeItemAtPath:filePath error:NULL];
                }
                suc = [self _manifestDeleteItemWithKey:item.key];
                total--;
            } else {
                break;
            }
            if (!suc) break;
        }
    } while (total > maxCount && items.count > 0 && suc);
    return suc;
}

- (BOOL)removeAllItems {
    [self _reset];
    return YES;
}

- (void)removeAllItemsWithProgressBlock:(nullable void(^)(int removeCount, int totalCount))progress
                               endBlock:(nullable void(^)(BOOL error))end {
    int total = [self _manifestGetTotalItemCount];
    if (total <= 0) {
        if (end) end(total < 0);
    } else {
        int left = total;
        int perCount = 32;
        NSArray *items = nil;
        BOOL suc = NO;
        do {
            items = [self _manifestGetItemSizeInfoOrderByTimeAscWithLimit:perCount];
            for (HJKVStorageItem *item in items) {
                if (left > 0) {
                    if (item.filename.length) {
                        [self _fileDeleteWithName:item.filename];
                    } else {
                        // 删除直接存储的文件
                        NSString *filePath = [self _filePathForKey:item.key];
                        [_fileManager removeItemAtPath:filePath error:NULL];
                    }
                    suc = [self _manifestDeleteItemWithKey:item.key];
                    left--;
                } else {
                    break;
                }
                if (!suc) break;
            }
            if (progress) progress(total - left, total);
        } while (left > 0 && items.count > 0 && suc);
        if (end) end(!suc);
    }
}

#pragma mark - Get Items

- (nullable HJKVStorageItem *)getItemForKey:(NSString *)key {
    if (key.length == 0) return nil;
    
    HJKVStorageItem *item = [self _manifestGetItemWithKey:key excludeInlineData:NO];
    if (item) {
        [self _manifestUpdateAccessTimeWithKey:key];
        if (item.filename.length) {
            item.value = [self _fileReadWithName:item.filename];
            if (!item.value) {
                [self _manifestDeleteItemWithKey:key];
                item = nil;
            }
        }
    }
    return item;
}

- (nullable HJKVStorageItem *)getItemInfoForKey:(NSString *)key {
    if (key.length == 0) return nil;
    HJKVStorageItem *item = [self _manifestGetItemWithKey:key excludeInlineData:YES];
    return item;
}

- (nullable NSData *)getItemValueForKey:(NSString *)key {
    if (key.length == 0) return nil;
    
    NSData *value = nil;
    switch (_type) {
        case HJKVStorageTypeFile: {
            NSString *filename = [self _manifestGetFilenameWithKey:key];
            if (filename.length) {
                value = [self _fileReadWithName:filename];
                if (!value) {
                    [self _manifestDeleteItemWithKey:key];
                    value = nil;
                }
            }
        } break;
        case HJKVStorageTypeInline: {
            value = [self _manifestGetValueWithKey:key];
        } break;
        case HJKVStorageTypeMixed: {
            NSString *filename = [self _manifestGetFilenameWithKey:key];
            if (filename.length) {
                value = [self _fileReadWithName:filename];
                if (!value) {
                    [self _manifestDeleteItemWithKey:key];
                    value = nil;
                }
            } else {
                value = [self _manifestGetValueWithKey:key];
            }
        } break;
    }
    if (value) {
        [self _manifestUpdateAccessTimeWithKey:key];
    }
    return value;
}

- (nullable NSArray<HJKVStorageItem *> *)getItemsForKeys:(NSArray<NSString *> *)keys {
    if (keys.count == 0) return nil;
    
    NSMutableArray *items = [self _manifestGetItemWithKeys:keys excludeInlineData:NO];
    if (_type != HJKVStorageTypeInline) {
        for (NSInteger i = 0, max = items.count; i < max; i++) {
            HJKVStorageItem *item = items[i];
            if (item.filename.length) {
                item.value = [self _fileReadWithName:item.filename];
                if (!item.value) {
                    if (item.key) [self _manifestDeleteItemWithKey:item.key];
                    [items removeObjectAtIndex:i];
                    i--;
                    max--;
                }
            }
        }
    }
    if (items.count > 0) {
        // 更新访问时间
        for (NSString *key in keys) {
            [self _manifestUpdateAccessTimeWithKey:key];
        }
    }
    return items.count ? items : nil;
}

- (nullable NSArray<HJKVStorageItem *> *)getItemInfoForKeys:(NSArray<NSString *> *)keys {
    if (keys.count == 0) return nil;
    return [self _manifestGetItemWithKeys:keys excludeInlineData:YES];
}

- (nullable NSDictionary<NSString *, NSData *> *)getItemValueForKeys:(NSArray<NSString *> *)keys {
    NSMutableArray *items = (NSMutableArray *)[self getItemsForKeys:keys];
    NSMutableDictionary *kv = [NSMutableDictionary new];
    for (HJKVStorageItem *item in items) {
        if (item.key && item.value) {
            [kv setObject:item.value forKey:item.key];
        }
    }
    return kv.count ? kv : nil;
}

#pragma mark - Get Storage Status

- (BOOL)itemExistForKey:(NSString *)key {
    if (key.length == 0) return NO;
    return [self _manifestGetItemCountWithKey:key] > 0;
}

- (int)getItemsCount {
    return [self _manifestGetTotalItemCount];
}

- (int)getItemsSize {
    return [self _manifestGetTotalItemSize];
}

@end
