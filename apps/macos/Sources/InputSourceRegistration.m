#import "InputSourceRegistration.h"
#import <AppKit/AppKit.h>
#include <limits.h>
#include <unistd.h>

int RefreshKeyboardSettingsCache(void) {
    if (getuid() == 0) {
        fprintf(stderr, "Run this command as your login user, without sudo.\n");
        return 1;
    }
    // The extension also retains an in-memory copy. Changing its disk cache
    // while Settings is open does not refresh the picker and can be overwritten.
    for (NSString *identifier in @[@"com.apple.systempreferences", @"com.apple.Keyboard-Settings.extension"]) {
        if ([NSRunningApplication runningApplicationsWithBundleIdentifier:identifier].count) {
            fprintf(stderr, "Quit System Settings, then run this command again. No cache was changed.\n");
            return 2;
        }
    }
    char cacheRoot[PATH_MAX];
    size_t length = confstr(_CS_DARWIN_USER_CACHE_DIR, cacheRoot, sizeof(cacheRoot));
    if (!length || length > sizeof(cacheRoot)) {
        fprintf(stderr, "Cannot locate the current user's input-source cache.\n");
        return 1;
    }
    NSString *path = [@(cacheRoot) stringByAppendingPathComponent:@"com.apple.Keyboard-Settings.extension/com.apple.IntlDataCache.le.kbdx"];
    NSFileManager *files = NSFileManager.defaultManager;
    NSError *error = nil;
    NSDictionary *attributes = [files attributesOfItemAtPath:path error:&error];
    if (!attributes) {
        if ([error.domain isEqual:NSCocoaErrorDomain] && error.code == NSFileReadNoSuchFileError) {
            printf("No cached input-source list exists; Keyboard Settings will create it.\n");
            return 0;
        }
        fprintf(stderr, "Cannot inspect input-source cache: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    if (![attributes[NSFileType] isEqual:NSFileTypeRegular] ||
        [attributes[NSFileOwnerAccountID] unsignedIntValue] != getuid()) {
        fprintf(stderr, "Refusing to change an unexpected cache file or owner.\n");
        return 1;
    }
    NSString *directory = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"]
        stringByAppendingPathComponent:@"local.inputmethod.DualLineIME/InputSourceCacheBackups"];
    if (![files createDirectoryAtPath:directory withIntermediateDirectories:YES
                          attributes:@{NSFilePosixPermissions:@0700} error:&error]) {
        fprintf(stderr, "Cannot create cache backup directory: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    NSString *backup = [directory stringByAppendingPathComponent:
        [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"kbdx"]];
    if (![files moveItemAtPath:path toPath:backup error:&error]) {
        fprintf(stderr, "Cannot back up input-source cache: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    printf("Backed up Keyboard Settings input-source cache: %s\n", backup.fileSystemRepresentation);
    printf("Reopen System Settings > Keyboard > Text Input > Edit > + > Others.\n");
    return 0;
}
