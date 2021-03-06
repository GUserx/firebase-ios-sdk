// Copyright 2019 Google
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "FIRCLSSettings.h"

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#if __has_include(<FBLPromises/FBLPromises.h>)
#import <FBLPromises/FBLPromises.h>
#else
#import "FBLPromises.h"
#endif

#import "FABMockApplicationIdentifierModel.h"
#import "FIRCLSFileManager.h"
#import "FIRCLSMockFileManager.h"

const NSString *FIRCLSTestSettingsActivated =
    @"{\"settings_version\":3,\"cache_duration\":60,\"features\":{\"collect_logged_exceptions\":"
    @"true,\"collect_reports\":true},\"app\":{\"status\":\"activated\",\"update_required\":false},"
    @"\"fabric\":{\"org_id\":\"010101000000111111111111\",\"bundle_id\":\"com.lets.test."
    @"crashlytics\"}}";

const NSString *FIRCLSTestSettingsInverse =
    @"{\"settings_version\":3,\"cache_duration\":12345,\"features\":{\"collect_logged_exceptions\":"
    @"false,\"collect_reports\":false},\"app\":{\"status\":\"new\",\"update_required\":true},"
    @"\"fabric\":{\"org_id\":\"01e101a0000011b113115111\",\"bundle_id\":\"im.from.the.server\"},"
    @"\"session\":{\"log_buffer_size\":128000,\"max_chained_exception_depth\":32,\"max_complete_"
    @"sessions_count\":4,\"max_custom_exception_events\":1000,\"max_custom_key_value_pairs\":2000,"
    @"\"identifier_mask\":255}}";

const NSString *FIRCLSTestSettingsCorrupted = @"{{{{ non_key: non\"value {}";

NSString *FIRCLSDefaultMockBuildInstanceID = @"12345abcdef";
NSString *FIRCLSDifferentMockBuildInstanceID = @"98765zyxwv";

NSString *const TestGoogleAppID = @"1:test:google:app:id";
NSString *const TestChangedGoogleAppID = @"2:changed:google:app:id";

@interface FIRCLSSettingsTests : XCTestCase

@property(nonatomic, retain) FIRCLSMockFileManager *fileManager;
@property(nonatomic, retain) FABMockApplicationIdentifierModel *appIDModel;

@property(nonatomic, retain) FIRCLSSettings *settings;

@end

@implementation FIRCLSSettingsTests

- (void)setUp {
  [super setUp];

  _fileManager = [[FIRCLSMockFileManager alloc] init];

  // Delete the cache
  [_fileManager removeItemAtPath:_fileManager.settingsFilePath];
  [_fileManager removeItemAtPath:_fileManager.settingsCacheKeyPath];

  _appIDModel = [[FABMockApplicationIdentifierModel alloc] init];
  _appIDModel.buildInstanceID = FIRCLSDefaultMockBuildInstanceID;

  _settings = [[FIRCLSSettings alloc] initWithFileManager:_fileManager appIDModel:_appIDModel];
}

- (void)testDefaultSettings {
  XCTAssertEqual(self.settings.isCacheExpired, YES);

  // Default to an hour
  XCTAssertEqual(self.settings.cacheDurationSeconds, 60 * 60);

  XCTAssertEqualObjects(self.settings.orgID, nil);
  XCTAssertEqualObjects(self.settings.fetchedBundleID, nil);

  XCTAssertFalse(self.settings.appNeedsOnboarding);
  XCTAssertFalse(self.settings.appUpdateRequired);

  XCTAssertTrue(self.settings.crashReportingEnabled);
  XCTAssertTrue(self.settings.errorReportingEnabled);
  XCTAssertTrue(self.settings.customExceptionsEnabled);

  XCTAssertEqual(self.settings.errorLogBufferSize, 64 * 1000);
  XCTAssertEqual(self.settings.logBufferSize, 64 * 1000);
  XCTAssertEqual(self.settings.maxCustomExceptions, 8);
  XCTAssertEqual(self.settings.maxCustomKeys, 64);
}

- (BOOL)writeSettings:(const NSString *)settings error:(NSError **)error {
  return [self writeSettings:settings error:error isCacheKey:NO];
}

- (BOOL)writeSettings:(const NSString *)settings
                error:(NSError **)error
           isCacheKey:(BOOL)isCacheKey {
  NSString *path = _fileManager.settingsFilePath;

  if (isCacheKey) {
    path = _fileManager.settingsCacheKeyPath;
  }

  // Create the directory.
  [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:error];
  if (*error != nil) {
    return NO;
  }

  // Create the file.
  [settings writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:error];
  return YES;
}

- (void)cacheSettingsWithGoogleAppID:(NSString *)googleAppID
                    currentTimestamp:(NSTimeInterval)currentTimestamp
                 expectedRemoveCount:(NSInteger)expectedRemoveCount {
  self.fileManager.removeExpectation = [[XCTestExpectation alloc]
      initWithDescription:@"FIRCLSMockFileManager.removeExpectation.cache"];
  self.fileManager.removeCount = 0;
  self.fileManager.expectedRemoveCount = expectedRemoveCount;

  [self.settings cacheSettingsWithGoogleAppID:googleAppID currentTimestamp:currentTimestamp];

  [self waitForExpectations:@[ self.fileManager.removeExpectation ] timeout:1];
}

- (void)reloadFromCacheWithGoogleAppID:(NSString *)googleAppID
                      currentTimestamp:(NSTimeInterval)currentTimestamp
                   expectedRemoveCount:(NSInteger)expectedRemoveCount {
  self.fileManager.removeExpectation = [[XCTestExpectation alloc]
      initWithDescription:@"FIRCLSMockFileManager.removeExpectation.reload"];
  self.fileManager.removeCount = 0;
  self.fileManager.expectedRemoveCount = expectedRemoveCount;

  [self.settings reloadFromCacheWithGoogleAppID:googleAppID currentTimestamp:currentTimestamp];

  [self waitForExpectations:@[ self.fileManager.removeExpectation ] timeout:1];
}

- (void)testActivatedSettingsCached {
  NSError *error = nil;
  [self writeSettings:FIRCLSTestSettingsActivated error:&error];
  XCTAssertNil(error, "%@", error);

  NSTimeInterval currentTimestamp = [NSDate timeIntervalSinceReferenceDate];
  [self.settings cacheSettingsWithGoogleAppID:TestGoogleAppID currentTimestamp:currentTimestamp];

  XCTAssertEqual(self.settings.isCacheExpired, NO);
  XCTAssertEqual(self.settings.cacheDurationSeconds, 60);

  XCTAssertEqualObjects(self.settings.orgID, @"010101000000111111111111");
  XCTAssertEqualObjects(self.settings.fetchedBundleID, @"com.lets.test.crashlytics");

  XCTAssertFalse(self.settings.appNeedsOnboarding);
  XCTAssertFalse(self.settings.appUpdateRequired);

  XCTAssertTrue(self.settings.crashReportingEnabled);
  XCTAssertTrue(self.settings.errorReportingEnabled);
  XCTAssertTrue(self.settings.customExceptionsEnabled);

  XCTAssertEqual(self.settings.errorLogBufferSize, 64 * 1000);
  XCTAssertEqual(self.settings.logBufferSize, 64 * 1000);
  XCTAssertEqual(self.settings.maxCustomExceptions, 8);
  XCTAssertEqual(self.settings.maxCustomKeys, 64);
}

- (void)testInverseDefaultSettingsCached {
  NSError *error = nil;
  [self writeSettings:FIRCLSTestSettingsInverse error:&error];
  XCTAssertNil(error, "%@", error);

  NSTimeInterval currentTimestamp = [NSDate timeIntervalSinceReferenceDate];
  [self.settings cacheSettingsWithGoogleAppID:TestGoogleAppID currentTimestamp:currentTimestamp];

  XCTAssertEqual(self.settings.isCacheExpired, NO);
  XCTAssertEqual(self.settings.cacheDurationSeconds, 12345);

  XCTAssertEqualObjects(self.settings.orgID, @"01e101a0000011b113115111");
  XCTAssertEqualObjects(self.settings.fetchedBundleID, @"im.from.the.server");

  XCTAssertTrue(self.settings.appNeedsOnboarding);
  XCTAssertTrue(self.settings.appUpdateRequired);

  XCTAssertFalse(self.settings.crashReportingEnabled);
  XCTAssertFalse(self.settings.errorReportingEnabled);
  XCTAssertFalse(self.settings.customExceptionsEnabled);

  XCTAssertEqual(self.settings.errorLogBufferSize, 128000);
  XCTAssertEqual(self.settings.logBufferSize, 128000);
  XCTAssertEqual(self.settings.maxCustomExceptions, 1000);
  XCTAssertEqual(self.settings.maxCustomKeys, 2000);
}

- (void)testCacheExpiredFromTTL {
  NSError *error = nil;
  [self writeSettings:FIRCLSTestSettingsActivated error:&error];
  XCTAssertNil(error, "%@", error);

  // 1 delete for clearing the cache key, plus 2 for the deletes from reloading and clearing the
  // cache and cache key
  self.fileManager.expectedRemoveCount = 3;

  NSTimeInterval currentTimestamp = [NSDate timeIntervalSinceReferenceDate];
  [self.settings cacheSettingsWithGoogleAppID:TestGoogleAppID currentTimestamp:currentTimestamp];

  // Go forward in time by 2x the cache duration
  NSTimeInterval futureTimestamp = currentTimestamp + (2 * self.settings.cacheDurationSeconds);
  [self.settings reloadFromCacheWithGoogleAppID:TestGoogleAppID currentTimestamp:futureTimestamp];

  XCTAssertEqual(self.settings.isCacheExpired, YES);

  // Since the TTL just expired, do not clear settings
  XCTAssertEqualObjects(self.settings.orgID, @"010101000000111111111111");
  XCTAssertEqualObjects(self.settings.fetchedBundleID, @"com.lets.test.crashlytics");
  XCTAssertEqual(self.settings.errorLogBufferSize, 64 * 1000);

  // Pretend we fetched settings again, but they had different values
  [self writeSettings:FIRCLSTestSettingsInverse error:&error];
  XCTAssertNil(error, "%@", error);

  // Cache the settings
  [self.settings cacheSettingsWithGoogleAppID:TestGoogleAppID currentTimestamp:currentTimestamp];

  // We should have the updated values that were fetched, and should not be expired
  XCTAssertEqual(self.settings.isCacheExpired, NO);
  XCTAssertEqualObjects(self.settings.orgID, @"01e101a0000011b113115111");
  XCTAssertEqualObjects(self.settings.fetchedBundleID, @"im.from.the.server");
  XCTAssertEqual(self.settings.errorLogBufferSize, 128000);
}

- (void)testCacheExpiredFromBuildInstanceID {
  NSError *error = nil;
  [self writeSettings:FIRCLSTestSettingsActivated error:&error];
  XCTAssertNil(error, "%@", error);

  // 1 delete for clearing the cache key, plus 2 for the deletes from reloading and clearing the
  // cache and cache key
  self.fileManager.expectedRemoveCount = 3;

  NSTimeInterval currentTimestamp = [NSDate timeIntervalSinceReferenceDate];
  [self.settings cacheSettingsWithGoogleAppID:TestGoogleAppID currentTimestamp:currentTimestamp];

  // Change the Build Instance ID
  self.appIDModel.buildInstanceID = FIRCLSDifferentMockBuildInstanceID;

  [self.settings reloadFromCacheWithGoogleAppID:TestGoogleAppID currentTimestamp:currentTimestamp];

  XCTAssertEqual(self.settings.isCacheExpired, YES);

  // Since the TTL just expired, do not clear settings
  XCTAssertEqualObjects(self.settings.orgID, @"010101000000111111111111");
  XCTAssertEqualObjects(self.settings.fetchedBundleID, @"com.lets.test.crashlytics");
  XCTAssertEqual(self.settings.errorLogBufferSize, 64 * 1000);

  // Pretend we fetched settings again, but they had different values
  [self writeSettings:FIRCLSTestSettingsInverse error:&error];
  XCTAssertNil(error, "%@", error);

  // Cache the settings
  [self.settings cacheSettingsWithGoogleAppID:TestGoogleAppID currentTimestamp:currentTimestamp];

  // We should have the updated values that were fetched, and should not be expired
  XCTAssertEqual(self.settings.isCacheExpired, NO);
  XCTAssertEqualObjects(self.settings.orgID, @"01e101a0000011b113115111");
  XCTAssertEqualObjects(self.settings.fetchedBundleID, @"im.from.the.server");
  XCTAssertEqual(self.settings.errorLogBufferSize, 128000);
}

- (void)testGoogleAppIDChanged {
  NSError *error = nil;
  [self writeSettings:FIRCLSTestSettingsInverse error:&error];
  XCTAssertNil(error, "%@", error);

  NSTimeInterval currentTimestamp = [NSDate timeIntervalSinceReferenceDate];
  [self.settings cacheSettingsWithGoogleAppID:TestGoogleAppID currentTimestamp:currentTimestamp];

  // Different Google App ID
  [self reloadFromCacheWithGoogleAppID:TestChangedGoogleAppID
                      currentTimestamp:currentTimestamp
                   expectedRemoveCount:2];

  XCTAssertEqual(self.settings.isCacheExpired, YES);

  // Clear the settings because they were for a different Google App ID
  XCTAssertEqualObjects(self.settings.orgID, nil);
  XCTAssertEqualObjects(self.settings.fetchedBundleID, nil);

  // Pretend we fetched settings again, but they had different values
  [self writeSettings:FIRCLSTestSettingsActivated error:&error];
  XCTAssertNil(error, "%@", error);

  // Cache the settings with the new Google App ID
  [self.settings cacheSettingsWithGoogleAppID:TestChangedGoogleAppID
                             currentTimestamp:currentTimestamp];

  // Should have new values and not expired
  XCTAssertEqual(self.settings.isCacheExpired, NO);
  XCTAssertEqualObjects(self.settings.orgID, @"010101000000111111111111");
  XCTAssertEqualObjects(self.settings.fetchedBundleID, @"com.lets.test.crashlytics");
  XCTAssertEqual(self.settings.errorLogBufferSize, 64 * 1000);
}

// This is a weird case where we got settings, but never created a cache key for it. We are treating
// this as if the cache was invalid and re-fetching in this case.
- (void)testActivatedSettingsMissingCacheKey {
  NSError *error = nil;
  [self writeSettings:FIRCLSTestSettingsActivated error:&error];
  XCTAssertNil(error, "%@", error);

  NSTimeInterval currentTimestamp = [NSDate timeIntervalSinceReferenceDate];

  // We only expect 1 removal because the cache key doesn't exist,
  // and deleteCachedSettings deletes the cache and the cache key
  [self reloadFromCacheWithGoogleAppID:TestGoogleAppID
                      currentTimestamp:currentTimestamp
                   expectedRemoveCount:1];

  XCTAssertEqual(self.settings.isCacheExpired, YES);
  XCTAssertEqual(self.settings.cacheDurationSeconds, 3600);

  XCTAssertEqualObjects(self.settings.orgID, nil);
  XCTAssertEqualObjects(self.settings.fetchedBundleID, nil);

  XCTAssertFalse(self.settings.appNeedsOnboarding);
  XCTAssertFalse(self.settings.appUpdateRequired);

  XCTAssertTrue(self.settings.crashReportingEnabled);
  XCTAssertTrue(self.settings.errorReportingEnabled);
  XCTAssertTrue(self.settings.customExceptionsEnabled);

  XCTAssertEqual(self.settings.errorLogBufferSize, 64 * 1000);
  XCTAssertEqual(self.settings.logBufferSize, 64 * 1000);
  XCTAssertEqual(self.settings.maxCustomExceptions, 8);
  XCTAssertEqual(self.settings.maxCustomKeys, 64);
}

// These tests are partially to make sure the SDK doesn't crash when it
// has corrupted settings.
- (void)testCorruptCache {
  // First write and load a good settings file
  NSError *error = nil;
  [self writeSettings:FIRCLSTestSettingsInverse error:&error];
  XCTAssertNil(error, "%@", error);

  NSTimeInterval currentTimestamp = [NSDate timeIntervalSinceReferenceDate];
  [self.settings cacheSettingsWithGoogleAppID:TestGoogleAppID currentTimestamp:currentTimestamp];

  // Should have "Inverse" values
  XCTAssertEqual(self.settings.isCacheExpired, NO);
  XCTAssertEqual(self.settings.cacheDurationSeconds, 12345);
  XCTAssertEqualObjects(self.settings.orgID, @"01e101a0000011b113115111");
  XCTAssertEqualObjects(self.settings.fetchedBundleID, @"im.from.the.server");
  XCTAssertTrue(self.settings.appNeedsOnboarding);
  XCTAssertEqual(self.settings.errorLogBufferSize, 128000);

  // Then write a corrupted one and cache + reload it
  [self writeSettings:FIRCLSTestSettingsCorrupted error:&error];
  XCTAssertNil(error, "%@", error);

  // Cache them, and reload. Since it's corrupted we should delete it all
  [self cacheSettingsWithGoogleAppID:TestGoogleAppID
                    currentTimestamp:currentTimestamp
                 expectedRemoveCount:2];

  // Should have default values because we deleted the cache and settingsDictionary
  XCTAssertEqual(self.settings.isCacheExpired, YES);
  XCTAssertEqual(self.settings.cacheDurationSeconds, 3600);
  XCTAssertEqualObjects(self.settings.orgID, nil);
  XCTAssertEqualObjects(self.settings.fetchedBundleID, nil);
  XCTAssertFalse(self.settings.appNeedsOnboarding);
  XCTAssertEqual(self.settings.errorLogBufferSize, 64 * 1000);
}

- (void)testCorruptCacheKey {
  // First write and load a good settings file
  NSError *error = nil;
  [self writeSettings:FIRCLSTestSettingsInverse error:&error];
  XCTAssertNil(error, "%@", error);

  NSTimeInterval currentTimestamp = [NSDate timeIntervalSinceReferenceDate];
  [self.settings cacheSettingsWithGoogleAppID:TestGoogleAppID currentTimestamp:currentTimestamp];

  // Should have "Inverse" values
  XCTAssertEqual(self.settings.isCacheExpired, NO);
  XCTAssertEqual(self.settings.cacheDurationSeconds, 12345);
  XCTAssertEqualObjects(self.settings.orgID, @"01e101a0000011b113115111");
  XCTAssertEqualObjects(self.settings.fetchedBundleID, @"im.from.the.server");
  XCTAssertTrue(self.settings.appNeedsOnboarding);
  XCTAssertEqual(self.settings.errorLogBufferSize, 128000);

  // Then pretend we wrote a corrupted cache key and just reload it
  [self writeSettings:FIRCLSTestSettingsCorrupted error:&error isCacheKey:YES];
  XCTAssertNil(error, "%@", error);

  // Since settings themselves are corrupted, delete it all
  [self reloadFromCacheWithGoogleAppID:TestGoogleAppID
                      currentTimestamp:currentTimestamp
                   expectedRemoveCount:2];

  // Should have default values because we deleted the cache and settingsDictionary
  XCTAssertEqual(self.settings.isCacheExpired, YES);
  XCTAssertEqual(self.settings.cacheDurationSeconds, 3600);
  XCTAssertEqualObjects(self.settings.orgID, nil);
  XCTAssertEqualObjects(self.settings.fetchedBundleID, nil);
  XCTAssertFalse(self.settings.appNeedsOnboarding);
  XCTAssertEqual(self.settings.errorLogBufferSize, 64 * 1000);
}

@end
