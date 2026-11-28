//  YKSBProbe.m — 只做一件事：在 SpringBoard 里 hook sendEvent:，把收到的事件写日志
//  不创建 runloop、不注入、不改系统行为，仅观测。
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static void SBLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"[%.3f] %@\n",
                      [[NSDate date] timeIntervalSince1970], msg];
    NSString *path = @"/var/mobile/Media/sbprobe.log";
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) { [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]; return; }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

typedef void (*SendEventFn)(id, SEL, UIEvent *);
static SendEventFn gOrigSendEvent = NULL;

static void YKSendEventHook(id self, SEL _cmd, UIEvent *event) {
    @autoreleasepool {
        NSSet *touches = nil;
        @try {
            touches = [event allTouches];
        } @catch (__unused NSException *e) { }

        if (touches.count > 0) {
            NSMutableString *desc = [NSMutableString string];
            for (UITouch *t in touches) {
                CGPoint p = CGPointZero;
                if ([t respondsToSelector:NSSelectorFromString(@"locationInWindow")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    NSValue *v = [t performSelector:NSSelectorFromString(@"locationInWindow")];
#pragma clang diagnostic pop
                    if ([v isKindOfClass:[NSValue class]]) p = [v CGPointValue];
                }
                [desc appendFormat:@"[phase=%ld x=%.1f y=%.1f] ",
                                   (long)t.phase, p.x, p.y];
            }
            SBLog(@"sendEvent touches=%lu %@", (unsigned long)touches.count, desc);
        }
    }
    if (gOrigSendEvent) gOrigSendEvent(self, _cmd, event);
}

__attribute__((constructor))
static void YKSBProbeInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @try {
            Method m = class_getInstanceMethod([UIApplication class], @selector(sendEvent:));
            if (!m) { SBLog(@"sendEvent: not found"); return; }
            gOrigSendEvent = (SendEventFn)method_getImplementation(m);
            method_setImplementation(m, (IMP)YKSendEventHook);
            SBLog(@"hook sendEvent: OK orig=%p", (void *)gOrigSendEvent);
        } @catch (NSException *e) {
            SBLog(@"hook failed: %@", e);
        }
    });
}
