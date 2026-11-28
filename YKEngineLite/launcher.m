//  yklaunch — 极小的 launcher，复刻 YKLaunchd 的角色
//  以 spawn-subsystem-root 权限 posix_spawn 守护进程，
//  让子进程进入 subsystem root 域，HID 事件才能进入 backboardd 输入管线。
#import <Foundation/Foundation.h>
#import <spawn.h>
#import <signal.h>
#import <sys/wait.h>
#include <stdio.h>
#include <unistd.h>

extern char **environ;

int main(int argc, char *argv[]) {
    @autoreleasepool {
        const char *daemonPath =
            "/var/containers/Bundle/Application/.jbroot-CF92D9BFDEEEFFF4/usr/bin/ykenginelite";

        FILE *lf = fopen("/var/mobile/Media/yklaunch.log", "a");
        #define LOG(fmt, ...) do { if (lf) { fprintf(lf, fmt "\n", ##__VA_ARGS__); fflush(lf); } } while (0)
        LOG("[yklaunch] start pid=%d euid=%d", getpid(), geteuid());

        pid_t pid = 0;
        posix_spawnattr_t attr;
        posix_spawnattr_init(&attr);

        short flags = POSIX_SPAWN_SETSID;
        posix_spawnattr_setflags(&attr, flags);

        // 继承环境
        char *childArgv[] = { (char *)daemonPath, NULL };
        int rc = posix_spawn(&pid, daemonPath, NULL, &attr, childArgv, environ);
        LOG("[yklaunch] posix_spawn rc=%d pid=%d", rc, pid);
        posix_spawnattr_destroy(&attr);

        if (rc != 0) {
            LOG("[yklaunch] spawn failed: %s", strerror(rc));
            return 1;
        }

        // 让 launcher 常驻，保活子进程
        int status = 0;
        for (;;) {
            pid_t w = waitpid(pid, &status, 0);
            LOG("[yklaunch] child exited w=%d status=%d", w, status);
            // 重启
            rc = posix_spawn(&pid, daemonPath, NULL, NULL, childArgv, environ);
            LOG("[yklaunch] respawn rc=%d pid=%d", rc, pid);
            if (rc != 0) break;
        }
        return 0;
    }
}
