#import "SSZipArchive.h"
#import <spawn.h>
#import <sys/wait.h>
#import <fcntl.h>

// Lite 实现：优先调用设备上的 zip/unzip CLI（Procursus 自带），否则返回失败并记录原因。
// 说明：原版使用 SSZipArchive（minizip）；此处只保证接口与行为契约，不重写压缩算法。

@implementation SSZipArchive

static int YKRunTool(NSString *tool, NSArray<NSString *> *args) {
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:tool]) return -1;
    NSMutableArray *argv = [NSMutableArray arrayWithObject:tool];
    [argv addObjectsFromArray:args];
    const char *cargv[32] = {0};
    NSUInteger n = MIN(argv.count, (NSUInteger)31);
    for (NSUInteger i = 0; i < n; i++) cargv[i] = [argv[i] fileSystemRepresentation];

    pid_t pid = 0;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0);
    int rc = posix_spawn(&pid, cargv[0], &actions, NULL, (char *const *)cargv, NULL);
    posix_spawn_file_actions_destroy(&actions);
    if (rc != 0 || pid <= 0) return -1;
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static NSString *YKFirstExisting(NSArray<NSString *> *paths) {
    for (NSString *p in paths) if ([[NSFileManager defaultManager] isExecutableFileAtPath:p]) return p;
    return nil;
}

+ (BOOL)createZipFileAtPath:(NSString *)path withContentsOfDirectory:(NSString *)dir {
    NSString *zip = YKFirstExisting(@[ @"/var/jb/usr/bin/zip", @"/usr/bin/zip" ]);
    if (!zip) { NSLog(@"[SSZipArchive] zip 不存在"); return NO; }
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"-r", @"-q", path, @".", nil];
    return YKRunTool(zip, args) == 0;
}

+ (BOOL)unzipFileAtPath:(NSString *)path toDestination:(NSString *)destination {
    NSString *unzip = YKFirstExisting(@[ @"/var/jb/usr/bin/unzip", @"/usr/bin/unzip" ]);
    if (!unzip) { NSLog(@"[SSZipArchive] unzip 不存在"); return NO; }
    [[NSFileManager defaultManager] createDirectoryAtPath:destination
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    return YKRunTool(unzip, @[ @"-o", @"-q", path, @"-d", destination ]) == 0;
}

+ (BOOL)unzipFileAtPath:(NSString *)path toDestination:(NSString *)destination
     preserveAttributes:(BOOL)preserve overwrite:(BOOL)overwrite nestedZipPath:(NSString *)nested
               password:(NSString *)password error:(NSError **)error
      completionHandler:(void (^)(NSString *, BOOL, NSError *))handler {
    BOOL ok = [self unzipFileAtPath:path toDestination:destination];
    if (!ok && error) {
        *error = [NSError errorWithDomain:@"SSZipArchive" code:1
                                 userInfo:@{NSLocalizedDescriptionKey: @"unzip 失败（可能缺 CLI 或加密）"}];
    }
    if (handler) handler(path.lastPathComponent, ok, ok ? nil : (error ? *error : nil));
    return ok;
}

@end
