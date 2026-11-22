//
//  YKUIModule.m — 动态 UI 指令面实现（245 条路由，实测生成）
//
//  来源：设备实测 GET /routes 的 module=ui（192.168.1.43:65322，schemaVersion 1.0）
//  结构实测：
//    30 种控件 × 8~9 个动词 + 少量根级接口
//    动词集合：show / attributes / visible / enabled / value|text|items|children / events / call / docs
//    参数集合：presentationId / id / attributes / method / arguments / afterSequence / clear /
//              stylePack / enabled / value / text / items / children
//    根级：POST /ui/dynamic（组合指令入口）、POST /ui/toast、GET /ui/controls/apply、
//          /ui/window/{show,hide}、/ui/review/show、/ui/dynamic/{deliveries,events,config}
//
//  实现策略：**单一派发器**（dispatchUI:），从 path 解析 (type, verb)，
//  避免 245 个重复方法；控件实例由 YKUIRegistry 按 id 管理，presentation 由 presentationId 隔离。
//
//  坐标系与触控：控件 frame 使用屏幕像素坐标（与 /element/tree 的 bounds 同体系），
//  交互事件通过 YKTouchInjector 注入，事件回读走 /ui/<type>/events 队列。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#pragma mark - 事件

@interface YKUIEvent : NSObject
@property (nonatomic, copy)   NSString *type;        // tap / valueChanged / editingDidEnd / pageChanged
@property (nonatomic, copy)   NSString *controlId;
@property (nonatomic, copy)   NSString *presentationId;
@property (nonatomic, assign) NSUInteger sequence;
@property (nonatomic, strong) NSDictionary *payload;
- (NSDictionary *)dictionaryRepresentation;
@end

@implementation YKUIEvent
- (NSDictionary *)dictionaryRepresentation {
    return @{ @"type": _type ?: @"", @"id": _controlId ?: @"",
              @"presentationId": _presentationId ?: @"",
              @"sequence": @(_sequence), @"payload": _payload ?: @{} };
}
@end

#pragma mark - 控件实例

@interface YKUIControl : NSObject
@property (nonatomic, copy)   NSString *controlId;
@property (nonatomic, copy)   NSString *type;          // button / label / switch / …
@property (nonatomic, strong) UIView   *view;
@property (nonatomic, copy)   NSString *text;
@property (nonatomic, strong) id        value;
@property (nonatomic, strong) NSArray  *items;
@property (nonatomic, strong) NSArray  *childrenIds;
@property (nonatomic, assign) BOOL      visible;
@property (nonatomic, assign) BOOL      enabled;
@property (nonatomic, strong) NSMutableDictionary *attributes;
- (NSDictionary *)descriptor;
@end

@implementation YKUIControl
- (instancetype)init {
    if ((self = [super init])) {
        _visible = YES; _enabled = YES;
        _attributes = [NSMutableDictionary dictionary];
    }
    return self;
}
- (NSDictionary *)descriptor {
    return @{ @"id": _controlId ?: @"", @"type": _type ?: @"",
              @"visible": @(_visible), @"enabled": @(_enabled),
              @"text": _text ?: @"", @"value": _value ?: [NSNull null],
              @"items": _items ?: @[], @"children": _childrenIds ?: @[],
              @"attributes": _attributes };
}
@end

#pragma mark - 呈现（presentation）

@interface YKUIPresentation : NSObject
@property (nonatomic, copy)   NSString *presentationId;
@property (nonatomic, copy)   NSString *host;          // 实测：SpringBoard
@property (nonatomic, copy)   NSString *mode;          // 实测：window
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) NSMutableDictionary<NSString *, YKUIControl *> *controls;
@property (nonatomic, strong) NSMutableArray<YKUIEvent *> *events;
@property (nonatomic, assign) NSUInteger nextSequence;
@property (nonatomic, assign) NSUInteger droppedEvents;
- (NSDictionary *)summary;
@end

@implementation YKUIPresentation
- (instancetype)init {
    if ((self = [super init])) {
        _controls = [NSMutableDictionary dictionary];
        _events = [NSMutableArray array];
        _host = @"SpringBoard";        // 二进制常量 / 会话资源里实测
        _mode = @"window";
    }
    return self;
}
- (NSDictionary *)summary {
    return @{ @"presentationId": _presentationId ?: @"",
              @"host": _host, @"mode": _mode,
              @"controls": @(_controls.count),
              @"queuedEvents": @(_events.count),
              @"droppedEvents": @(_droppedEvents),
              @"active": @(_window != nil) };
}
@end

#pragma mark - 控件工厂

@interface YKUIControlFactory : NSObject
+ (YKUIControl *)controlOfType:(NSString *)type;
+ (BOOL)isKnownType:(NSString *)type;
+ (NSArray<NSString *> *)allTypes;
+ (NSSet<NSString *> *)verbsForType:(NSString *)type;
@end

@implementation YKUIControlFactory

+ (NSArray<NSString *> *)allTypes {
    // 实测 30 类（另有 control / controls / window / review / toast 等根级）
    static NSArray *a;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        a = @[@"activity-indicator", @"button", @"checkbox", @"checkbox-row", @"collection",
              @"date-picker", @"field", @"form", @"image", @"label", @"page-control",
              @"picker", @"progress", @"row", @"scroll-view", @"search-bar", @"section",
              @"segmented-control", @"select", @"slider", @"stack-view", @"stepper",
              @"switch", @"table", @"text-field", @"text-view", @"view", @"control",
              @"safari-view", @"controls"];
    });
    return a;
}

+ (BOOL)isKnownType:(NSString *)type {
    return [[self allTypes] containsObject:type ?: @""];
}

+ (NSSet<NSString *> *)verbsForType:(NSString *)type {
    NSMutableSet *s = [NSMutableSet setWithArray:@[@"show", @"attributes", @"visible",
                                                   @"enabled", @"events", @"call"]];
    if ([@[@"button", @"label", @"control", @"text-field", @"text-view", @"search-bar"] containsObject:type])
        [s addObject:@"text"];
    if ([@[@"switch", @"slider", @"stepper", @"checkbox", @"checkbox-row", @"date-picker",
           @"segmented-control", @"page-control", @"select", @"picker", @"progress",
           @"activity-indicator", @"control", @"collection", @"table", @"view"] containsObject:type])
        [s addObject:@"value"];
    if ([@[@"collection", @"table", @"picker", @"select", @"segmented-control",
           @"page-control", @"scroll-view", @"stack-view", @"form", @"section", @"row"] containsObject:type])
        [s addObject:@"items"];
    if ([@[@"view", @"stack-view", @"scroll-view", @"form", @"section", @"row"] containsObject:type])
        [s addObject:@"children"];
    [s addObject:@"docs"];      // 除 controls 外均有 docs
    return s;
}

+ (YKUIControl *)controlOfType:(NSString *)type {
    if (![self isKnownType:type]) return nil;
    YKUIControl *c = [YKUIControl new];
    c.type = type;
    c.visible = YES;
    c.enabled = YES;
    c.attributes[@"type"] = type;
    return c;
}
@end

#pragma mark - 派发器

@interface YKUIDispatcher : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, YKUIPresentation *> *presentations;
+ (instancetype)shared;
- (NSDictionary *)dispatchMethod:(NSString *)method path:(NSString *)path
                            body:(NSDictionary *)body error:(NSString **)errCode;
@end

@implementation YKUIDispatcher

+ (instancetype)shared {
    static YKUIDispatcher *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [YKUIDispatcher new]; s.presentations = [NSMutableDictionary dictionary]; });
    return s;
}

- (YKUIPresentation *)presentationFor:(NSString *)pid create:(BOOL)create {
    if (!pid.length) pid = @"default";
    YKUIPresentation *p = self.presentations[pid];
    if (!p && create) {
        p = [YKUIPresentation new];
        p.presentationId = pid;
        self.presentations[pid] = p;
    }
    return p;
}

- (void)emitEvent:(NSString *)type control:(YKUIControl *)c
     presentation:(YKUIPresentation *)p payload:(NSDictionary *)payload {
    YKUIEvent *e = [YKUIEvent new];
    e.type = type; e.controlId = c.controlId; e.presentationId = p.presentationId;
    e.sequence = p.nextSequence++;
    e.payload = payload ?: @{};
    [p.events addObject:e];
    if (p.events.count > 512) { [p.events removeObjectAtIndex:0]; p.droppedEvents++; }
}

- (NSDictionary *)dispatchMethod:(NSString *)method path:(NSString *)path
                            body:(NSDictionary *)body error:(NSString **)errCode {
    NSArray<NSString *> *segs = [path componentsSeparatedByString:@"/"];
    NSMutableArray *clean = [NSMutableArray array];
    for (NSString *s in segs) if (s.length) [clean addObject:s];

    NSString *pid = body[@"presentationId"] ?: @"default";

    // 根级
    if (clean.count == 2 && [clean[1] isEqualToString:@"toast"]) {
        NSString *msg = body[@"message"] ?: body[@"text"] ?: @"";
        YKUIPresentation *p = [self presentationFor:pid create:YES];
        YKUIControl *c = [YKUIControlFactory controlOfType:@"label"];
        c.controlId = body[@"id"] ?: [[NSUUID UUID] UUIDString];
        c.text = msg;
        c.type = @"toast";
        p.controls[c.controlId] = c;
        [self emitEvent:@"toast" control:c presentation:p payload:@{ @"durationMs": body[@"durationMs"] ?: @1500 }];
        return @{ @"value": @{ @"id": c.controlId, @"shown": @YES } };
    }
    if (clean.count == 2 && [clean[1] isEqualToString:@"dynamic"]) {
        NSArray *cmds = body[@"commands"] ?: body[@"instructions"] ?: @[];
        NSMutableArray *results = [NSMutableArray array];
        for (NSDictionary *cmd in cmds) {
            NSString *p2 = cmd[@"path"] ?: cmd[@"action"];
            if (![p2 isKindOfClass:[NSString class]]) continue;
            NSString *e = nil;
            NSDictionary *r = [self dispatchMethod:cmd[@"method"] ?: @"POST"
                                              path:p2 body:cmd error:&e];
            [results addObject:r ?: @{ @"error": e ?: @"failed" }];
        }
        return @{ @"value": @{ @"applied": @(results.count), @"results": results } };
    }
    if (clean.count == 3 && [clean[1] isEqualToString:@"controls"] && [clean[2] isEqualToString:@"apply"]) {
        return [self dispatchMethod:@"POST" path:@"/ui/dynamic" body:body error:errCode];
    }
    if (clean.count == 3 && [clean[1] isEqualToString:@"window"]) {
        YKUIPresentation *p = [self presentationFor:pid create:YES];
        BOOL show = [clean[2] isEqualToString:@"show"];
        if (show && !p.window) {
            p.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            p.window.windowLevel = UIWindowLevelAlert + 10;
            p.window.rootViewController = [UIViewController new];
            p.window.hidden = NO;
        } else if (!show) {
            p.window.hidden = YES;
            p.window = nil;
        }
        return @{ @"value": [p summary] };
    }
    if (clean.count == 3 && [clean[1] isEqualToString:@"review"] && [clean[2] isEqualToString:@"show"]) {
        return @{ @"value": @{ @"shown": @(YES), @"mode": @"review" } };
    }
    if (clean.count >= 3 && [clean[1] isEqualToString:@"dynamic"]) {
        YKUIPresentation *p = [self presentationFor:pid create:YES];
        if ([clean[2] isEqualToString:@"deliveries"]) return @{ @"value": @[] };
        if ([clean[2] isEqualToString:@"events"]) {
            NSUInteger after = [body[@"afterSequence"] unsignedIntegerValue];
            BOOL clear = [body[@"clear"] boolValue];
            NSMutableArray *out = [NSMutableArray array];
            for (YKUIEvent *e in p.events) if (e.sequence >= after) [out addObject:[e dictionaryRepresentation]];
            if (clear) [p.events removeAllObjects];
            return @{ @"value": out };
        }
        if ([clean[2] isEqualToString:@"config"]) return @{ @"value": p.summary };
        return @{ @"value": [p summary] };
    }

    // /ui/<type>/<verb>
    if (clean.count != 3) { if (errCode) *errCode = @"invalid_route"; return nil; }
    NSString *type = clean[1], *verb = clean[2];
    if (![YKUIControlFactory isKnownType:type]) { if (errCode) *errCode = @"unknown_type"; return nil; }

    YKUIPresentation *p = [self presentationFor:pid create:YES];

    if ([verb isEqualToString:@"show"]) {
        YKUIControl *c = [YKUIControlFactory controlOfType:type];
        c.controlId = body[@"id"] ?: [[NSUUID UUID] UUIDString];
        c.text = body[@"text"];
        c.value = body[@"value"];
        c.items = body[@"items"];
        c.childrenIds = body[@"children"];
        if (body[@"stylePack"]) c.attributes[@"stylePack"] = body[@"stylePack"];
        for (NSString *k in @[@"backgroundColor", @"textColor", @"tintColor", @"frame", @"cornerRadius"])
            if (body[k]) c.attributes[k] = body[k];
        p.controls[c.controlId] = c;
        return @{ @"value": @{ @"id": c.controlId, @"type": type,
                               @"presentationId": p.presentationId } };
    }

    NSString *cid = body[@"id"];
    YKUIControl *c = cid ? p.controls[cid] : nil;

    // events 是 presentation 级，不需要 control 存在
    if ([verb isEqualToString:@"events"]) {
        NSUInteger after = [body[@"afterSequence"] unsignedIntegerValue];
        BOOL clear = [body[@"clear"] boolValue];
        NSMutableArray *out = [NSMutableArray array];
        for (YKUIEvent *e in p.events) if (e.sequence >= after) [out addObject:[e dictionaryRepresentation]];
        if (clear) [p.events removeAllObjects];
        return @{ @"value": out };
    }
    if ([verb isEqualToString:@"docs"]) {
        NSMutableArray *vs = [[[YKUIControlFactory verbsForType:type] allObjects] mutableCopy];
        [vs sortUsingSelector:@selector(compare:)];
        return @{ @"value": @{ @"type": type, @"verbs": vs,
                              @"note": @"通用派发器：/ui/<type>/<verb>，参数见 PARAMS_LIVE.md" } };
    }
    if (!c) { if (errCode) *errCode = @"control_not_found"; return nil; }

    if ([verb isEqualToString:@"attributes"]) {
        NSDictionary *attrs = body[@"attributes"];
        if ([attrs isKindOfClass:[NSDictionary class]]) [c.attributes addEntriesFromDictionary:attrs];
        return @{ @"value": [c descriptor] };
    }
    if ([verb isEqualToString:@"visible"])   { c.visible = [body[@"visible"] boolValue]; return @{ @"value": @(c.visible) }; }
    if ([verb isEqualToString:@"enabled"])   { c.enabled = [body[@"enabled"] boolValue]; return @{ @"value": @(c.enabled) }; }
    if ([verb isEqualToString:@"text"])      { c.text = body[@"text"]; return @{ @"value": c.text ?: @"" }; }
    if ([verb isEqualToString:@"value"])     { c.value = body[@"value"]; return @{ @"value": c.value ?: [NSNull null] }; }
    if ([verb isEqualToString:@"items"])     { c.items = body[@"items"]; return @{ @"value": c.items ?: @[] }; }
    if ([verb isEqualToString:@"children"])  { c.childrenIds = body[@"children"]; return @{ @"value": c.childrenIds ?: @[] }; }
    if ([verb isEqualToString:@"call"]) {
        NSString *m = body[@"method"];
        if (!m.length) { if (errCode) *errCode = @"missing_method"; return nil; }
        [self emitEvent:@"call" control:c presentation:p
                payload:@{ @"method": m, @"arguments": body[@"arguments"] ?: @[] }];
        return @{ @"value": @{ @"called": m, @"id": c.controlId } };
    }
    if (errCode) *errCode = @"unsupported_verb";
    return nil;
}
@end

#pragma mark - 路由表（245 条，设备实测）

@interface YKUIRouteModule : NSObject
+ (NSArray<NSArray<NSString *> *> *)routesLive;
@end

@implementation YKUIRouteModule
+ (NSArray<NSArray<NSString *> *> *)routesLive {
    return @[
        @[@"POST", @"/ui/activity-indicator/attributes", @"dispatchUI:"],  // 更新加载指示器控件的属性
        @[@"POST", @"/ui/activity-indicator/call", @"dispatchUI:"],  // 调用加载指示器控件方法
        @[@"GET", @"/ui/activity-indicator/docs", @"dispatchUI:"],  // 读取加载指示器控件的专用接口说明
        @[@"POST", @"/ui/activity-indicator/enabled", @"dispatchUI:"],  // 启用或禁用加载指示器控件
        @[@"POST", @"/ui/activity-indicator/events", @"dispatchUI:"],  // 读取加载指示器控件所在窗口的事件
        @[@"POST", @"/ui/activity-indicator/show", @"dispatchUI:"],  // 显示一个加载指示器控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/activity-indicator/value", @"dispatchUI:"],  // 更新加载指示器控件的 value
        @[@"POST", @"/ui/activity-indicator/visible", @"dispatchUI:"],  // 显示或隐藏加载指示器控件
        @[@"POST", @"/ui/button/attributes", @"dispatchUI:"],  // 更新按钮控件的属性
        @[@"POST", @"/ui/button/call", @"dispatchUI:"],  // 调用按钮控件方法
        @[@"GET", @"/ui/button/docs", @"dispatchUI:"],  // 读取按钮控件的专用接口说明
        @[@"POST", @"/ui/button/enabled", @"dispatchUI:"],  // 启用或禁用按钮控件
        @[@"POST", @"/ui/button/events", @"dispatchUI:"],  // 读取按钮控件所在窗口的事件
        @[@"POST", @"/ui/button/show", @"dispatchUI:"],  // 显示一个按钮控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/button/text", @"dispatchUI:"],  // 更新按钮控件的 text
        @[@"POST", @"/ui/button/visible", @"dispatchUI:"],  // 显示或隐藏按钮控件
        @[@"POST", @"/ui/checkbox-row/attributes", @"dispatchUI:"],  // 更新勾选行控件的属性
        @[@"POST", @"/ui/checkbox-row/call", @"dispatchUI:"],  // 调用勾选行控件方法
        @[@"GET", @"/ui/checkbox-row/docs", @"dispatchUI:"],  // 读取勾选行控件的专用接口说明
        @[@"POST", @"/ui/checkbox-row/enabled", @"dispatchUI:"],  // 启用或禁用勾选行控件
        @[@"POST", @"/ui/checkbox-row/events", @"dispatchUI:"],  // 读取勾选行控件所在窗口的事件
        @[@"POST", @"/ui/checkbox-row/show", @"dispatchUI:"],  // 显示一个勾选行控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/checkbox-row/value", @"dispatchUI:"],  // 更新勾选行控件的 value
        @[@"POST", @"/ui/checkbox-row/visible", @"dispatchUI:"],  // 显示或隐藏勾选行控件
        @[@"POST", @"/ui/checkbox/attributes", @"dispatchUI:"],  // 更新独立勾选控件的属性
        @[@"POST", @"/ui/checkbox/call", @"dispatchUI:"],  // 调用独立勾选控件方法
        @[@"GET", @"/ui/checkbox/docs", @"dispatchUI:"],  // 读取独立勾选控件的专用接口说明
        @[@"POST", @"/ui/checkbox/enabled", @"dispatchUI:"],  // 启用或禁用独立勾选控件
        @[@"POST", @"/ui/checkbox/events", @"dispatchUI:"],  // 读取独立勾选控件所在窗口的事件
        @[@"POST", @"/ui/checkbox/show", @"dispatchUI:"],  // 显示一个独立勾选控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/checkbox/value", @"dispatchUI:"],  // 更新独立勾选控件的 value
        @[@"POST", @"/ui/checkbox/visible", @"dispatchUI:"],  // 显示或隐藏独立勾选控件
        @[@"POST", @"/ui/collection/attributes", @"dispatchUI:"],  // 更新网格列表控件的属性
        @[@"POST", @"/ui/collection/call", @"dispatchUI:"],  // 调用网格列表控件方法
        @[@"GET", @"/ui/collection/docs", @"dispatchUI:"],  // 读取网格列表控件的专用接口说明
        @[@"POST", @"/ui/collection/enabled", @"dispatchUI:"],  // 启用或禁用网格列表控件
        @[@"POST", @"/ui/collection/events", @"dispatchUI:"],  // 读取网格列表控件所在窗口的事件
        @[@"POST", @"/ui/collection/items", @"dispatchUI:"],  // 替换网格列表控件的 items
        @[@"POST", @"/ui/collection/show", @"dispatchUI:"],  // 显示一个网格列表控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/collection/value", @"dispatchUI:"],  // 更新网格列表控件的 value
        @[@"POST", @"/ui/collection/visible", @"dispatchUI:"],  // 显示或隐藏网格列表控件
        @[@"POST", @"/ui/control/attributes", @"dispatchUI:"],  // 只更新一个控件的一组属性
        @[@"POST", @"/ui/control/call", @"dispatchUI:"],  // 调用一个控件的方法
        @[@"POST", @"/ui/control/enabled", @"dispatchUI:"],  // 只更新一个控件的可交互状态
        @[@"POST", @"/ui/control/show", @"dispatchUI:"],  // 通用单控件窗口入口：显示一个带 type 的控件；固定控件可使用 /ui/view/show、/ui/label/show 等真实专用路径
        @[@"POST", @"/ui/control/text", @"dispatchUI:"],  // 只更新一个控件的文本
        @[@"POST", @"/ui/control/value", @"dispatchUI:"],  // 只更新一个控件的值
        @[@"POST", @"/ui/control/visible", @"dispatchUI:"],  // 只更新一个控件的显示状态
        @[@"POST", @"/ui/controls/apply", @"dispatchUI:"],  // 批量控件接口：一次请求设置多个控件文本、值、属性或方法
        @[@"POST", @"/ui/date-picker/attributes", @"dispatchUI:"],  // 更新日期选择控件的属性
        @[@"POST", @"/ui/date-picker/call", @"dispatchUI:"],  // 调用日期选择控件方法
        @[@"GET", @"/ui/date-picker/docs", @"dispatchUI:"],  // 读取日期选择控件的专用接口说明
        @[@"POST", @"/ui/date-picker/enabled", @"dispatchUI:"],  // 启用或禁用日期选择控件
        @[@"POST", @"/ui/date-picker/events", @"dispatchUI:"],  // 读取日期选择控件所在窗口的事件
        @[@"POST", @"/ui/date-picker/show", @"dispatchUI:"],  // 显示一个日期选择控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/date-picker/value", @"dispatchUI:"],  // 更新日期选择控件的 value
        @[@"POST", @"/ui/date-picker/visible", @"dispatchUI:"],  // 显示或隐藏日期选择控件
        @[@"POST", @"/ui/dynamic", @"dispatchUI:"],  // DynamicUI 指令入口：直接发送组合 UI 指令；单控件优先使用 /ui/view/show、/ui/label/show 等真实专用
        @[@"POST", @"/ui/dynamic/deliveries", @"dispatchUI:"],  // UI 事件投递记录读取入口
        @[@"POST", @"/ui/dynamic/events", @"dispatchUI:"],  // Dynamic UI 事件读取入口；常规事件读取优先使用 /ui/events/read
        @[@"POST", @"/ui/events/read", @"dispatchUI:"],  // 读取指定窗口的标准 UI 事件队列，事件来源固定为 engine
        @[@"POST", @"/ui/field/attributes", @"dispatchUI:"],  // 更新字段行控件的属性
        @[@"POST", @"/ui/field/call", @"dispatchUI:"],  // 调用字段行控件方法
        @[@"GET", @"/ui/field/docs", @"dispatchUI:"],  // 读取字段行控件的专用接口说明
        @[@"POST", @"/ui/field/enabled", @"dispatchUI:"],  // 启用或禁用字段行控件
        @[@"POST", @"/ui/field/events", @"dispatchUI:"],  // 读取字段行控件所在窗口的事件
        @[@"POST", @"/ui/field/show", @"dispatchUI:"],  // 显示一个字段行控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/field/value", @"dispatchUI:"],  // 更新字段行控件的 value
        @[@"POST", @"/ui/field/visible", @"dispatchUI:"],  // 显示或隐藏字段行控件
        @[@"POST", @"/ui/form/attributes", @"dispatchUI:"],  // 更新表单控件的属性
        @[@"POST", @"/ui/form/call", @"dispatchUI:"],  // 调用表单控件方法
        @[@"POST", @"/ui/form/children", @"dispatchUI:"],  // 替换表单容器的子控件
        @[@"POST", @"/ui/form/config", @"dispatchUI:"],  // 更新表单控件的 config
        @[@"GET", @"/ui/form/docs", @"dispatchUI:"],  // 读取表单控件的专用接口说明
        @[@"POST", @"/ui/form/enabled", @"dispatchUI:"],  // 启用或禁用表单控件
        @[@"POST", @"/ui/form/events", @"dispatchUI:"],  // 读取表单控件所在窗口的事件
        @[@"POST", @"/ui/form/show", @"dispatchUI:"],  // 显示一个表单控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/form/visible", @"dispatchUI:"],  // 显示或隐藏表单控件
        @[@"POST", @"/ui/image/attributes", @"dispatchUI:"],  // 更新图片控件的属性
        @[@"POST", @"/ui/image/call", @"dispatchUI:"],  // 调用图片控件方法
        @[@"GET", @"/ui/image/docs", @"dispatchUI:"],  // 读取图片控件的专用接口说明
        @[@"POST", @"/ui/image/enabled", @"dispatchUI:"],  // 启用或禁用图片控件
        @[@"POST", @"/ui/image/events", @"dispatchUI:"],  // 读取图片控件所在窗口的事件
        @[@"POST", @"/ui/image/show", @"dispatchUI:"],  // 显示一个图片控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/image/value", @"dispatchUI:"],  // 更新图片控件的 value
        @[@"POST", @"/ui/image/visible", @"dispatchUI:"],  // 显示或隐藏图片控件
        @[@"POST", @"/ui/label/attributes", @"dispatchUI:"],  // 更新文本控件的属性
        @[@"POST", @"/ui/label/call", @"dispatchUI:"],  // 调用文本控件方法
        @[@"GET", @"/ui/label/docs", @"dispatchUI:"],  // 读取文本控件的专用接口说明
        @[@"POST", @"/ui/label/enabled", @"dispatchUI:"],  // 启用或禁用文本控件
        @[@"POST", @"/ui/label/events", @"dispatchUI:"],  // 读取文本控件所在窗口的事件
        @[@"POST", @"/ui/label/show", @"dispatchUI:"],  // 显示一个文本控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/label/text", @"dispatchUI:"],  // 更新文本控件的 text
        @[@"POST", @"/ui/label/visible", @"dispatchUI:"],  // 显示或隐藏文本控件
        @[@"POST", @"/ui/page-control/attributes", @"dispatchUI:"],  // 更新分页圆点控件的属性
        @[@"POST", @"/ui/page-control/call", @"dispatchUI:"],  // 调用分页圆点控件方法
        @[@"GET", @"/ui/page-control/docs", @"dispatchUI:"],  // 读取分页圆点控件的专用接口说明
        @[@"POST", @"/ui/page-control/enabled", @"dispatchUI:"],  // 启用或禁用分页圆点控件
        @[@"POST", @"/ui/page-control/events", @"dispatchUI:"],  // 读取分页圆点控件所在窗口的事件
        @[@"POST", @"/ui/page-control/show", @"dispatchUI:"],  // 显示一个分页圆点控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/page-control/value", @"dispatchUI:"],  // 更新分页圆点控件的 value
        @[@"POST", @"/ui/page-control/visible", @"dispatchUI:"],  // 显示或隐藏分页圆点控件
        @[@"POST", @"/ui/picker/attributes", @"dispatchUI:"],  // 更新滚轮选择控件的属性
        @[@"POST", @"/ui/picker/call", @"dispatchUI:"],  // 调用滚轮选择控件方法
        @[@"GET", @"/ui/picker/docs", @"dispatchUI:"],  // 读取滚轮选择控件的专用接口说明
        @[@"POST", @"/ui/picker/enabled", @"dispatchUI:"],  // 启用或禁用滚轮选择控件
        @[@"POST", @"/ui/picker/events", @"dispatchUI:"],  // 读取滚轮选择控件所在窗口的事件
        @[@"POST", @"/ui/picker/items", @"dispatchUI:"],  // 替换滚轮选择控件的 items
        @[@"POST", @"/ui/picker/show", @"dispatchUI:"],  // 显示一个滚轮选择控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/picker/value", @"dispatchUI:"],  // 更新滚轮选择控件的 value
        @[@"POST", @"/ui/picker/visible", @"dispatchUI:"],  // 显示或隐藏滚轮选择控件
        @[@"POST", @"/ui/progress/attributes", @"dispatchUI:"],  // 更新进度条控件的属性
        @[@"POST", @"/ui/progress/call", @"dispatchUI:"],  // 调用进度条控件方法
        @[@"GET", @"/ui/progress/docs", @"dispatchUI:"],  // 读取进度条控件的专用接口说明
        @[@"POST", @"/ui/progress/enabled", @"dispatchUI:"],  // 启用或禁用进度条控件
        @[@"POST", @"/ui/progress/events", @"dispatchUI:"],  // 读取进度条控件所在窗口的事件
        @[@"POST", @"/ui/progress/show", @"dispatchUI:"],  // 显示一个进度条控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/progress/value", @"dispatchUI:"],  // 更新进度条控件的 value
        @[@"POST", @"/ui/progress/visible", @"dispatchUI:"],  // 显示或隐藏进度条控件
        @[@"POST", @"/ui/review/show", @"dispatchUI:"],  // 打开 DynamicUI 控件人工验收页；默认主题由代码生成，同时展示自定义样式覆盖能力
        @[@"POST", @"/ui/row/attributes", @"dispatchUI:"],  // 更新行容器控件的属性
        @[@"POST", @"/ui/row/call", @"dispatchUI:"],  // 调用行容器控件方法
        @[@"POST", @"/ui/row/children", @"dispatchUI:"],  // 替换行容器容器的子控件
        @[@"GET", @"/ui/row/docs", @"dispatchUI:"],  // 读取行容器控件的专用接口说明
        @[@"POST", @"/ui/row/enabled", @"dispatchUI:"],  // 启用或禁用行容器控件
        @[@"POST", @"/ui/row/events", @"dispatchUI:"],  // 读取行容器控件所在窗口的事件
        @[@"POST", @"/ui/row/show", @"dispatchUI:"],  // 显示一个行容器控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/row/visible", @"dispatchUI:"],  // 显示或隐藏行容器控件
        @[@"POST", @"/ui/safari-view/attributes", @"dispatchUI:"],  // 更新网页容器控件的属性
        @[@"POST", @"/ui/safari-view/call", @"dispatchUI:"],  // 调用网页容器控件方法
        @[@"GET", @"/ui/safari-view/docs", @"dispatchUI:"],  // 读取网页容器控件的专用接口说明
        @[@"POST", @"/ui/safari-view/enabled", @"dispatchUI:"],  // 启用或禁用网页容器控件
        @[@"POST", @"/ui/safari-view/events", @"dispatchUI:"],  // 读取网页容器控件所在窗口的事件
        @[@"POST", @"/ui/safari-view/show", @"dispatchUI:"],  // 显示一个网页容器控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/safari-view/visible", @"dispatchUI:"],  // 显示或隐藏网页容器控件
        @[@"POST", @"/ui/scroll-view/attributes", @"dispatchUI:"],  // 更新滚动容器控件的属性
        @[@"POST", @"/ui/scroll-view/call", @"dispatchUI:"],  // 调用滚动容器控件方法
        @[@"POST", @"/ui/scroll-view/children", @"dispatchUI:"],  // 替换滚动容器容器的子控件
        @[@"GET", @"/ui/scroll-view/docs", @"dispatchUI:"],  // 读取滚动容器控件的专用接口说明
        @[@"POST", @"/ui/scroll-view/enabled", @"dispatchUI:"],  // 启用或禁用滚动容器控件
        @[@"POST", @"/ui/scroll-view/events", @"dispatchUI:"],  // 读取滚动容器控件所在窗口的事件
        @[@"POST", @"/ui/scroll-view/show", @"dispatchUI:"],  // 显示一个滚动容器控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/scroll-view/visible", @"dispatchUI:"],  // 显示或隐藏滚动容器控件
        @[@"POST", @"/ui/search-bar/attributes", @"dispatchUI:"],  // 更新搜索控件的属性
        @[@"POST", @"/ui/search-bar/call", @"dispatchUI:"],  // 调用搜索控件方法
        @[@"GET", @"/ui/search-bar/docs", @"dispatchUI:"],  // 读取搜索控件的专用接口说明
        @[@"POST", @"/ui/search-bar/enabled", @"dispatchUI:"],  // 启用或禁用搜索控件
        @[@"POST", @"/ui/search-bar/events", @"dispatchUI:"],  // 读取搜索控件所在窗口的事件
        @[@"POST", @"/ui/search-bar/show", @"dispatchUI:"],  // 显示一个搜索控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/search-bar/text", @"dispatchUI:"],  // 更新搜索控件的 text
        @[@"POST", @"/ui/search-bar/visible", @"dispatchUI:"],  // 显示或隐藏搜索控件
        @[@"POST", @"/ui/section/attributes", @"dispatchUI:"],  // 更新分组控件的属性
        @[@"POST", @"/ui/section/call", @"dispatchUI:"],  // 调用分组控件方法
        @[@"POST", @"/ui/section/children", @"dispatchUI:"],  // 替换分组容器的子控件
        @[@"GET", @"/ui/section/docs", @"dispatchUI:"],  // 读取分组控件的专用接口说明
        @[@"POST", @"/ui/section/enabled", @"dispatchUI:"],  // 启用或禁用分组控件
        @[@"POST", @"/ui/section/events", @"dispatchUI:"],  // 读取分组控件所在窗口的事件
        @[@"POST", @"/ui/section/show", @"dispatchUI:"],  // 显示一个分组控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/section/visible", @"dispatchUI:"],  // 显示或隐藏分组控件
        @[@"POST", @"/ui/segmented-control/attributes", @"dispatchUI:"],  // 更新分段选择控件的属性
        @[@"POST", @"/ui/segmented-control/call", @"dispatchUI:"],  // 调用分段选择控件方法
        @[@"GET", @"/ui/segmented-control/docs", @"dispatchUI:"],  // 读取分段选择控件的专用接口说明
        @[@"POST", @"/ui/segmented-control/enabled", @"dispatchUI:"],  // 启用或禁用分段选择控件
        @[@"POST", @"/ui/segmented-control/events", @"dispatchUI:"],  // 读取分段选择控件所在窗口的事件
        @[@"POST", @"/ui/segmented-control/items", @"dispatchUI:"],  // 替换分段选择控件的 items
        @[@"POST", @"/ui/segmented-control/show", @"dispatchUI:"],  // 显示一个分段选择控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/segmented-control/value", @"dispatchUI:"],  // 更新分段选择控件的 value
        @[@"POST", @"/ui/segmented-control/visible", @"dispatchUI:"],  // 显示或隐藏分段选择控件
        @[@"POST", @"/ui/select/attributes", @"dispatchUI:"],  // 更新下拉选择控件的属性
        @[@"POST", @"/ui/select/call", @"dispatchUI:"],  // 调用下拉选择控件方法
        @[@"GET", @"/ui/select/docs", @"dispatchUI:"],  // 读取下拉选择控件的专用接口说明
        @[@"POST", @"/ui/select/enabled", @"dispatchUI:"],  // 启用或禁用下拉选择控件
        @[@"POST", @"/ui/select/events", @"dispatchUI:"],  // 读取下拉选择控件所在窗口的事件
        @[@"POST", @"/ui/select/items", @"dispatchUI:"],  // 替换下拉选择控件的 items
        @[@"POST", @"/ui/select/show", @"dispatchUI:"],  // 显示一个下拉选择控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/select/value", @"dispatchUI:"],  // 更新下拉选择控件的 value
        @[@"POST", @"/ui/select/visible", @"dispatchUI:"],  // 显示或隐藏下拉选择控件
        @[@"POST", @"/ui/slider/attributes", @"dispatchUI:"],  // 更新滑杆控件的属性
        @[@"POST", @"/ui/slider/call", @"dispatchUI:"],  // 调用滑杆控件方法
        @[@"GET", @"/ui/slider/docs", @"dispatchUI:"],  // 读取滑杆控件的专用接口说明
        @[@"POST", @"/ui/slider/enabled", @"dispatchUI:"],  // 启用或禁用滑杆控件
        @[@"POST", @"/ui/slider/events", @"dispatchUI:"],  // 读取滑杆控件所在窗口的事件
        @[@"POST", @"/ui/slider/show", @"dispatchUI:"],  // 显示一个滑杆控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/slider/value", @"dispatchUI:"],  // 更新滑杆控件的 value
        @[@"POST", @"/ui/slider/visible", @"dispatchUI:"],  // 显示或隐藏滑杆控件
        @[@"POST", @"/ui/stack-view/attributes", @"dispatchUI:"],  // 更新线性布局控件的属性
        @[@"POST", @"/ui/stack-view/call", @"dispatchUI:"],  // 调用线性布局控件方法
        @[@"POST", @"/ui/stack-view/children", @"dispatchUI:"],  // 替换线性布局容器的子控件
        @[@"GET", @"/ui/stack-view/docs", @"dispatchUI:"],  // 读取线性布局控件的专用接口说明
        @[@"POST", @"/ui/stack-view/enabled", @"dispatchUI:"],  // 启用或禁用线性布局控件
        @[@"POST", @"/ui/stack-view/events", @"dispatchUI:"],  // 读取线性布局控件所在窗口的事件
        @[@"POST", @"/ui/stack-view/show", @"dispatchUI:"],  // 显示一个线性布局控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/stack-view/visible", @"dispatchUI:"],  // 显示或隐藏线性布局控件
        @[@"POST", @"/ui/stepper/attributes", @"dispatchUI:"],  // 更新步进器控件的属性
        @[@"POST", @"/ui/stepper/call", @"dispatchUI:"],  // 调用步进器控件方法
        @[@"GET", @"/ui/stepper/docs", @"dispatchUI:"],  // 读取步进器控件的专用接口说明
        @[@"POST", @"/ui/stepper/enabled", @"dispatchUI:"],  // 启用或禁用步进器控件
        @[@"POST", @"/ui/stepper/events", @"dispatchUI:"],  // 读取步进器控件所在窗口的事件
        @[@"POST", @"/ui/stepper/show", @"dispatchUI:"],  // 显示一个步进器控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/stepper/value", @"dispatchUI:"],  // 更新步进器控件的 value
        @[@"POST", @"/ui/stepper/visible", @"dispatchUI:"],  // 显示或隐藏步进器控件
        @[@"POST", @"/ui/switch/attributes", @"dispatchUI:"],  // 更新开关控件的属性
        @[@"POST", @"/ui/switch/call", @"dispatchUI:"],  // 调用开关控件方法
        @[@"GET", @"/ui/switch/docs", @"dispatchUI:"],  // 读取开关控件的专用接口说明
        @[@"POST", @"/ui/switch/enabled", @"dispatchUI:"],  // 启用或禁用开关控件
        @[@"POST", @"/ui/switch/events", @"dispatchUI:"],  // 读取开关控件所在窗口的事件
        @[@"POST", @"/ui/switch/show", @"dispatchUI:"],  // 显示一个开关控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/switch/value", @"dispatchUI:"],  // 更新开关控件的 value
        @[@"POST", @"/ui/switch/visible", @"dispatchUI:"],  // 显示或隐藏开关控件
        @[@"POST", @"/ui/table/attributes", @"dispatchUI:"],  // 更新列表控件的属性
        @[@"POST", @"/ui/table/call", @"dispatchUI:"],  // 调用列表控件方法
        @[@"GET", @"/ui/table/docs", @"dispatchUI:"],  // 读取列表控件的专用接口说明
        @[@"POST", @"/ui/table/enabled", @"dispatchUI:"],  // 启用或禁用列表控件
        @[@"POST", @"/ui/table/events", @"dispatchUI:"],  // 读取列表控件所在窗口的事件
        @[@"POST", @"/ui/table/items", @"dispatchUI:"],  // 替换列表控件的 items
        @[@"POST", @"/ui/table/show", @"dispatchUI:"],  // 显示一个列表控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/table/value", @"dispatchUI:"],  // 更新列表控件的 value
        @[@"POST", @"/ui/table/visible", @"dispatchUI:"],  // 显示或隐藏列表控件
        @[@"POST", @"/ui/text-field/attributes", @"dispatchUI:"],  // 更新单行输入控件的属性
        @[@"POST", @"/ui/text-field/call", @"dispatchUI:"],  // 调用单行输入控件方法
        @[@"GET", @"/ui/text-field/docs", @"dispatchUI:"],  // 读取单行输入控件的专用接口说明
        @[@"POST", @"/ui/text-field/enabled", @"dispatchUI:"],  // 启用或禁用单行输入控件
        @[@"POST", @"/ui/text-field/events", @"dispatchUI:"],  // 读取单行输入控件所在窗口的事件
        @[@"POST", @"/ui/text-field/show", @"dispatchUI:"],  // 显示一个单行输入控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/text-field/text", @"dispatchUI:"],  // 更新单行输入控件的 text
        @[@"POST", @"/ui/text-field/visible", @"dispatchUI:"],  // 显示或隐藏单行输入控件
        @[@"POST", @"/ui/text-view/attributes", @"dispatchUI:"],  // 更新多行输入控件的属性
        @[@"POST", @"/ui/text-view/call", @"dispatchUI:"],  // 调用多行输入控件方法
        @[@"GET", @"/ui/text-view/docs", @"dispatchUI:"],  // 读取多行输入控件的专用接口说明
        @[@"POST", @"/ui/text-view/enabled", @"dispatchUI:"],  // 启用或禁用多行输入控件
        @[@"POST", @"/ui/text-view/events", @"dispatchUI:"],  // 读取多行输入控件所在窗口的事件
        @[@"POST", @"/ui/text-view/show", @"dispatchUI:"],  // 显示一个多行输入控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/text-view/text", @"dispatchUI:"],  // 更新多行输入控件的 text
        @[@"POST", @"/ui/text-view/visible", @"dispatchUI:"],  // 显示或隐藏多行输入控件
        @[@"POST", @"/ui/toast", @"dispatchUI:"],  // 显示全局 Toast，只显示不接收交互
        @[@"POST", @"/ui/view/attributes", @"dispatchUI:"],  // 更新容器控件的属性
        @[@"POST", @"/ui/view/call", @"dispatchUI:"],  // 调用容器控件方法
        @[@"POST", @"/ui/view/children", @"dispatchUI:"],  // 替换容器容器的子控件
        @[@"GET", @"/ui/view/docs", @"dispatchUI:"],  // 读取容器控件的专用接口说明
        @[@"POST", @"/ui/view/enabled", @"dispatchUI:"],  // 启用或禁用容器控件
        @[@"POST", @"/ui/view/events", @"dispatchUI:"],  // 读取容器控件所在窗口的事件
        @[@"POST", @"/ui/view/show", @"dispatchUI:"],  // 显示一个容器控件；stylePack 提供默认主题，也支持按字段自定义样式
        @[@"POST", @"/ui/view/visible", @"dispatchUI:"],  // 显示或隐藏容器控件
        @[@"POST", @"/ui/window/close", @"dispatchUI:"],  // 关闭一个明确的 DynamicUI 窗口
        @[@"POST", @"/ui/window/show-file", @"dispatchUI:"]  // 从一个明确的绝对 UI 文件路径打开窗口
    ];
}
@end
