//
//  ViewController.m
//  HJCacheDemo
//
//  Created by navy on 2019/3/1.
//  Copyright © 2019 navy. All rights reserved.
//

#import "ViewController.h"
#import <HJCache/HJKVStorage.h>

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    // 延迟执行测试，确保界面加载完成
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self runHJKVStorageTests];
    });
}

- (void)runHJKVStorageTests {
    NSLog(@"开始测试改造后的 HJKVStorage...");
    
    // 创建临时目录
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"HJCacheTest"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // 清理之前的测试目录
    if ([fileManager fileExistsAtPath:tempDir]) {
        [fileManager removeItemAtPath:tempDir error:nil];
    }
    
    // 测试 File 类型
    NSLog(@"测试 HJKVStorageTypeFile...");
    HJKVStorage *fileStorage = [[HJKVStorage alloc] initWithPath:tempDir type:HJKVStorageTypeFile];
    if (fileStorage) {
        NSLog(@"✓ File 类型存储创建成功");
        
        // 测试保存数据
        NSString *testKey = @"test_key";
        NSData *testData = [@"Hello, HJCache!" dataUsingEncoding:NSUTF8StringEncoding];
        BOOL saveResult = [fileStorage saveItemWithKey:testKey value:testData filename:@"test_key_Hello_HJCache" extendedData:nil];
        NSLog(@"保存数据: %@", saveResult ? @"✓ 成功" : @"✗ 失败");
        
        // 测试读取数据
        NSData *readData = [fileStorage getItemValueForKey:testKey];
        if (readData) {
            NSString *readString = [[NSString alloc] initWithData:readData encoding:NSUTF8StringEncoding];
            NSLog(@"读取数据: ✓ 成功 - %@", readString);
        } else {
            NSLog(@"读取数据: ✗ 失败");
        }
        
        // 测试检查存在性
        BOOL exists = [fileStorage itemExistForKey:testKey];
        NSLog(@"检查存在性: %@", exists ? @"✓ 存在" : @"✗ 不存在");
        
        // 测试获取统计信息
        int count = [fileStorage getItemsCount];
        int size = [fileStorage getItemsSize];
        NSLog(@"统计信息: 数量=%d, 大小=%d", count, size);
        
        // 测试删除数据
        BOOL deleteResult = [fileStorage removeItemForKey:testKey];
        NSLog(@"删除数据: %@", deleteResult ? @"✓ 成功" : @"✗ 失败");
        
        // 验证删除
        exists = [fileStorage itemExistForKey:testKey];
        NSLog(@"删除后检查: %@", exists ? @"✗ 仍然存在" : @"✓ 已删除");
    } else {
        NSLog(@"✗ File 类型存储创建失败");
    }
    
    // 测试 Inline 类型（数据直接存储在文件中）
    NSLog(@"\n测试 HJKVStorageTypeInline...");
    NSString *inlineTempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"HJCacheInlineTest"];
    if ([fileManager fileExistsAtPath:inlineTempDir]) {
        [fileManager removeItemAtPath:inlineTempDir error:nil];
    }
    
    HJKVStorage *inlineStorage = [[HJKVStorage alloc] initWithPath:inlineTempDir type:HJKVStorageTypeInline];
    if (inlineStorage) {
        NSLog(@"✓ Inline 类型存储创建成功");
        
        // 测试保存数据
        NSString *testKey2 = @"test_key2";
        NSData *testData2 = [@"Hello, Inline Mode!" dataUsingEncoding:NSUTF8StringEncoding];
        BOOL saveResult2 = [inlineStorage saveItemWithKey:testKey2 value:testData2];
        NSLog(@"保存数据: %@", saveResult2 ? @"✓ 成功" : @"✗ 失败");
        
        // 测试读取数据
        NSData *readData2 = [inlineStorage getItemValueForKey:testKey2];
        if (readData2) {
            NSString *readString2 = [[NSString alloc] initWithData:readData2 encoding:NSUTF8StringEncoding];
            NSLog(@"读取数据: ✓ 成功 - %@", readString2);
        } else {
            NSLog(@"读取数据: ✗ 失败");
        }
    } else {
        NSLog(@"✗ Inline 类型存储创建失败");
    }
    
    // 测试 Mixed 类型
    NSLog(@"\n测试 HJKVStorageTypeMixed...");
    NSString *mixedTempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"HJCacheMixedTest"];
    if ([fileManager fileExistsAtPath:mixedTempDir]) {
        [fileManager removeItemAtPath:mixedTempDir error:nil];
    }
    
    HJKVStorage *mixedStorage = [[HJKVStorage alloc] initWithPath:mixedTempDir type:HJKVStorageTypeMixed];
    if (mixedStorage) {
        NSLog(@"✓ Mixed 类型存储创建成功");
        
        // 测试保存数据（带文件名）
        NSString *testKey3 = @"test_key3";
        NSData *testData3 = [@"Hello, Mixed Mode!" dataUsingEncoding:NSUTF8StringEncoding];
        BOOL saveResult3 = [mixedStorage saveItemWithKey:testKey3 value:testData3 filename:@"test_file.txt" extendedData:nil];
        NSLog(@"保存数据（带文件名）: %@", saveResult3 ? @"✓ 成功" : @"✗ 失败");
        
        // 测试读取数据
        HJKVStorageItem *item = [mixedStorage getItemForKey:testKey3];
        if (item && item.value) {
            NSString *readString3 = [[NSString alloc] initWithData:item.value encoding:NSUTF8StringEncoding];
            NSLog(@"读取数据: ✓ 成功 - %@", readString3);
            NSLog(@"文件信息: 文件名=%@, 大小=%d", item.filename, item.size);
        } else {
            NSLog(@"读取数据: ✗ 失败");
        }
    } else {
        NSLog(@"✗ Mixed 类型存储创建失败");
    }
    
    NSLog(@"\n测试完成！");
    
    // 在界面上显示测试结果
    [self showTestResults];
}

- (void)showTestResults {
    // 创建一个简单的文本视图来显示测试结果
    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(20, 100, self.view.frame.size.width - 40, self.view.frame.size.height - 120)];
    textView.backgroundColor = [UIColor lightGrayColor];
    textView.textColor = [UIColor blackColor];
    textView.font = [UIFont systemFontOfSize:12];
    textView.editable = NO;
    textView.text = @"HJKVStorage 测试已完成！\n\n请查看控制台输出以获取详细的测试结果。\n\n测试内容包括：\n• HJKVStorageTypeFile 类型功能\n• HJKVStorageTypeInline 类型功能\n• HJKVStorageTypeMixed 类型功能\n• 基本的增删改查操作\n• 统计信息获取\n\n所有测试都基于 NSFileManager 实现。";
    
    [self.view addSubview:textView];
}

@end
