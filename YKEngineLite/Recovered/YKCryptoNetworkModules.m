//
//  YKCryptoNetworkModules.m — 加密 / 网络 / 服务级 / 引擎配置（76 条路由，实测生成）
//
//  来源：设备实测 GET /routes（192.168.1.43:65322，schemaVersion 1.0）
//    crypto(21)   统一参数：data / key / iv / aad / encoding / inputEncoding / keyEncoding / outputEncoding
//    network(21)  请求 / cookie / 代理 / 上传下载 / 默认值
//    http(32)     executor 18 + session 10 + health/routes/status + OPTIONS + wda/shutdown
//    internal(2)  引擎配置读写
//
//  说明：参数名来自实测 schema；具体默认值与边界（如 digest 默认算法、AES 默认模式）标 [推断]。
//

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonHMAC.h>
#import <Security/Security.h>

#pragma mark - 通用工具

static NSData *YKDataFromAny(id v, NSString *inputEncoding) {
    if ([v isKindOfClass:[NSData class]]) return v;
    if (![v isKindOfClass:[NSString class]]) return nil;
    NSString *s = v;
    NSString *enc = (inputEncoding ?: @"utf8").lowercaseString;
    if ([enc isEqualToString:@"base64"]) return [[NSData alloc] initWithBase64EncodedString:s options:0];
    if ([enc isEqualToString:@"hex"]) {
        NSMutableData *d = [NSMutableData data];
        const char *c = s.UTF8String;
        for (NSUInteger i = 0; i + 1 < s.length; i += 2) {
            unsigned int b = 0;
            sscanf(c + i, "%2x", &b);
            [d appendBytes:&b length:1];
        }
        return d;
    }
    return [s dataUsingEncoding:NSUTF8StringEncoding];
}

static id YKEncodeData(NSData *d, NSString *outputEncoding) {
    NSString *enc = (outputEncoding ?: @"base64").lowercaseString;
    if (!d) return [NSNull null];
    if ([enc isEqualToString:@"hex"]) {
        NSMutableString *h = [NSMutableString string];
        const uint8_t *p = d.bytes;
        for (NSUInteger i = 0; i < d.length; i++) [h appendFormat:@"%02x", p[i]];
        return h;
    }
    if ([enc isEqualToString:@"utf8"]) {
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        return s ?: [d base64EncodedStringWithOptions:0];
    }
    return [d base64EncodedStringWithOptions:0];
}


// PEM / DER 通用解析（PKCS#1 与 SPKI 都尝试）
static SecKeyRef YKSecKeyFromPEM(NSString *pem, CFStringRef keyClass) {
    if (!pem.length) return NULL;
    NSString *b64 = pem;
    if ([pem rangeOfString:@"-----BEGIN"].location != NSNotFound) {
        NSMutableArray *lines = [NSMutableArray array];
        for (NSString *l in [pem componentsSeparatedByString:@"\n"]) {
            if ([l hasPrefix:@"-----"]) continue;
            [lines addObject:[l stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
        }
        b64 = [lines componentsJoinedByString:@""];
    }
    NSData *der = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    if (!der) return NULL;
    NSArray *types = @[ (__bridge id)kSecAttrKeyTypeRSA, (__bridge id)kSecAttrKeyTypeECSECPrimeRandom ];
    for (id t in types) {
        NSDictionary *attrs = @{ (__bridge id)kSecAttrKeyType: t,
                                 (__bridge id)kSecAttrKeyClass: (__bridge id)keyClass };
        CFErrorRef e = NULL;
        SecKeyRef k = SecKeyCreateWithData((__bridge CFDataRef)der, (__bridge CFDictionaryRef)attrs, &e);
        if (k) return k;
    }
    return NULL;
}

static NSDictionary *YKValue(id v) { return @{ @"value": v ?: [NSNull null] }; }
// 实测（2026-11）：错误包封是 {"value":{"error":…,"message":…}}，不是 {"value.error":…}
static NSDictionary *YKError(NSString *code, NSString *msg) {
    return @{ @"value": @{ @"error": code ?: @"invalid argument", @"message": msg ?: @"" } };
}

#pragma mark =============== CRYPTO（21） ===============

@interface YKCryptoModule : NSObject
@end

@implementation YKCryptoModule

// ===== 参数名全部来自实机探测（tools/param_probe.py）=====
// digest      : data, algorithm(必填, sha256/md5/sha1/sha512) → hex
// hmac        : data, key, algorithm
// pbkdf2      : password, salt, algorithm, iterations, outputLength
// hkdf        : ikm, salt?, info?, algorithm, outputLength
// encrypt     : plainData, algorithm ∈ {AES, DES, 3DES}, key, iv? → {encoding,data,size}
// decrypt     : cipherData, algorithm, key, iv?
// gcm/encrypt : plainData, key, iv → {tag:{encoding,data,size}, cipherData:{…}}
// rsa/encrypt : plainData, publicKeyPEM      rsa/decrypt : cipherData, privateKeyPEM
// sign        : data, privateKeyPEM          verify      : data, signature, publicKeyPEM
// randomBytes : length(默认16) → {encoding,data,size}

+ (NSDictionary *)base64Encode:(NSDictionary *)b {
    NSData *d = YKDataFromAny(b[@"data"], b[@"inputEncoding"]);
    return d ? YKValue([d base64EncodedStringWithOptions:0]) : YKError(@"invalid argument", @"缺少必填参数: data");
}
+ (NSDictionary *)base64Decode:(NSDictionary *)b {
    id src = b[@"base64"] ?: b[@"data"];
    if (!src) return YKError(@"invalid argument", @"缺少必填参数: base64 (Base64 文本)");
    NSData *d = YKDataFromAny(src, @"base64");
    return d ? YKValue(YKEncodeData(d, b[@"outputEncoding"] ?: @"utf8"))
             : YKError(@"invalid argument", @"参数错误: base64 长度不合法");
}
+ (NSDictionary *)hexEncode:(NSDictionary *)b {
    NSData *d = YKDataFromAny(b[@"data"], b[@"inputEncoding"]);
    return d ? YKValue(YKEncodeData(d, @"hex")) : YKError(@"invalid argument", @"缺少必填参数: data");
}
+ (NSDictionary *)hexDecode:(NSDictionary *)b {
    id src = b[@"hex"] ?: b[@"data"];
    if (!src) return YKError(@"invalid argument", @"缺少必填参数: hex (十六进制文本)");
    NSData *d = YKDataFromAny(src, @"hex");
    return d ? YKValue(YKEncodeData(d, b[@"outputEncoding"] ?: @"utf8"))
             : YKError(@"invalid argument", @"参数错误: hex 长度不合法");
}
+ (NSDictionary *)urlEncode:(NSDictionary *)b {
    NSString *t = [b[@"text"] ?: b[@"data"] description];
    if (!t.length) return YKError(@"invalid argument", @"缺少必填参数: text (URL 原始文本)");
    return YKValue([t stringByAddingPercentEncodingWithAllowedCharacters:
                    [NSCharacterSet URLQueryAllowedCharacterSet]] ?: t);
}
+ (NSDictionary *)urlDecode:(NSDictionary *)b {
    NSString *t = [b[@"text"] ?: b[@"data"] description];
    if (!t.length) return YKError(@"invalid argument", @"缺少必填参数: text (URL 编码文本)");
    return YKValue([t stringByRemovingPercentEncoding] ?: t);
}

+ (NSDictionary *)digest:(NSDictionary *)b {
    NSString *algo = [b[@"algorithm"] lowercaseString];
    if (!algo.length) return YKError(@"invalid argument", @"缺少必填参数: algorithm (摘要算法)");
    NSData *d = YKDataFromAny(b[@"data"], b[@"inputEncoding"]);
    if (!d) return YKError(@"invalid argument", @"缺少必填参数: data");
    unsigned char buf[CC_SHA512_DIGEST_LENGTH] = {0};
    NSUInteger len = 0;
    if ([algo isEqualToString:@"md5"]) { CC_MD5(d.bytes, (CC_LONG)d.length, buf); len = CC_MD5_DIGEST_LENGTH; }
    else if ([algo isEqualToString:@"sha1"]) { CC_SHA1(d.bytes, (CC_LONG)d.length, buf); len = CC_SHA1_DIGEST_LENGTH; }
    else if ([algo isEqualToString:@"sha512"]) { CC_SHA512(d.bytes, (CC_LONG)d.length, buf); len = CC_SHA512_DIGEST_LENGTH; }
    else { CC_SHA256(d.bytes, (CC_LONG)d.length, buf); len = CC_SHA256_DIGEST_LENGTH; }
    return YKValue(YKEncodeData([NSData dataWithBytes:buf length:len], @"hex"));
}

+ (NSDictionary *)hmac:(NSDictionary *)b {
    NSString *algo = [b[@"algorithm"] lowercaseString];
    if (!algo.length) return YKError(@"invalid argument", @"缺少必填参数: algorithm (摘要算法)");
    NSData *d = YKDataFromAny(b[@"data"], b[@"inputEncoding"]);
    NSData *k = YKDataFromAny(b[@"key"], b[@"keyEncoding"]);
    if (!d || !k) return YKError(@"invalid argument", @"缺少必填参数: data/key");
    CCHmacAlgorithm a = kCCHmacAlgSHA256;
    NSUInteger len = CC_SHA256_DIGEST_LENGTH;
    if ([algo isEqualToString:@"sha1"]) { a = kCCHmacAlgSHA1; len = CC_SHA1_DIGEST_LENGTH; }
    else if ([algo isEqualToString:@"sha512"]) { a = kCCHmacAlgSHA512; len = CC_SHA512_DIGEST_LENGTH; }
    else if ([algo isEqualToString:@"md5"]) { a = kCCHmacAlgMD5; len = CC_MD5_DIGEST_LENGTH; }
    unsigned char buf[CC_SHA512_DIGEST_LENGTH] = {0};
    CCHmac(a, k.bytes, k.length, d.bytes, d.length, buf);
    return YKValue(YKEncodeData([NSData dataWithBytes:buf length:len], @"hex"));
}

+ (NSDictionary *)pbkdf2:(NSDictionary *)b {
    NSData *pwd = YKDataFromAny(b[@"password"] ?: b[@"data"], b[@"inputEncoding"]);
    NSData *salt = YKDataFromAny(b[@"salt"], b[@"keyEncoding"]);
    NSNumber *outLen = b[@"outputLength"] ?: b[@"length"];
    if (![outLen isKindOfClass:[NSNumber class]])
        return YKError(@"invalid argument", @"参数错误: outputLength 必须是有限数字");
    if (!pwd) return YKError(@"invalid argument", @"缺少必填参数: password");
    NSString *algo = [b[@"algorithm"] ?: @"sha256" lowercaseString];
    CCPseudoRandomAlgorithm prf = kCCPRFHmacAlgSHA256;
    if ([algo isEqualToString:@"sha1"]) prf = kCCPRFHmacAlgSHA1;
    else if ([algo isEqualToString:@"sha512"]) prf = kCCPRFHmacAlgSHA512;
    NSMutableData *out = [NSMutableData dataWithLength:outLen.unsignedIntegerValue];
    int rc = CCKeyDerivationPBKDF(kCCPBKDF2, pwd.bytes, pwd.length,
                                  salt.bytes, salt.length ?: 0, prf,
                                  (uint)[b[@"iterations"] unsignedIntValue] ?: 10000,
                                  out.mutableBytes, out.length);
    return rc == 0 ? YKValue(@{ @"encoding": @"base64",
                                @"data": [out base64EncodedStringWithOptions:0],
                                @"size": @(out.length) })
                   : YKError(@"invalid argument", @"pbkdf2 失败");
}

+ (NSDictionary *)hkdf:(NSDictionary *)b {
    NSData *ikm = YKDataFromAny(b[@"ikm"] ?: b[@"data"], b[@"inputEncoding"]);
    NSNumber *outLen = b[@"outputLength"] ?: b[@"length"];
    if (![outLen isKindOfClass:[NSNumber class]])
        return YKError(@"invalid argument", @"参数错误: outputLength 必须是有限数字");
    if (!ikm) return YKError(@"invalid argument", @"缺少必填参数: ikm");
    NSData *salt = YKDataFromAny(b[@"salt"], b[@"keyEncoding"]) ?: [NSMutableData dataWithLength:32];
    NSData *info = YKDataFromAny(b[@"info"], @"utf8") ?: [NSData data];

    unsigned char prk[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, salt.bytes, salt.length, ikm.bytes, ikm.length, prk);
    NSMutableData *okm = [NSMutableData data];
    NSMutableData *t = [NSMutableData data];
    uint8_t counter = 1;
    while (okm.length < outLen.unsignedIntegerValue) {
        NSMutableData *input = [NSMutableData dataWithData:t];
        [input appendData:info];
        [input appendBytes:&counter length:1];
        unsigned char out[CC_SHA256_DIGEST_LENGTH];
        CCHmac(kCCHmacAlgSHA256, prk, sizeof(prk), input.bytes, input.length, out);
        t = [NSMutableData dataWithBytes:out length:sizeof(out)];
        [okm appendData:t];
        counter++;
    }
    NSData *slice = [okm subdataWithRange:NSMakeRange(0, outLen.unsignedIntegerValue)];
    return YKValue(@{ @"encoding": @"base64",
                      @"data": [slice base64EncodedStringWithOptions:0],
                      @"size": @(slice.length) });
}

// algorithm 仅支持 AES / DES / 3DES（实测错误文案）
+ (NSDictionary *)blockCipher:(NSDictionary *)b encrypt:(BOOL)enc {
    NSString *algo = [b[@"algorithm"] uppercaseString] ?: @"";
    if (![@[@"AES", @"DES", @"3DES"] containsObject:algo])
        return YKError(@"invalid argument", @"参数错误: algorithm 仅支持 AES/DES/3DES");
    NSData *data = YKDataFromAny(enc ? (b[@"plainData"] ?: b[@"data"]) : (b[@"cipherData"] ?: b[@"data"]),
                                 enc ? (b[@"inputEncoding"] ?: @"utf8") : @"base64");
    NSData *key = YKDataFromAny(b[@"key"], b[@"keyEncoding"]);
    NSData *iv  = YKDataFromAny(b[@"iv"], b[@"keyEncoding"]);
    if (!data) return YKError(@"invalid argument", @"缺少必填参数: plainData/cipherData");
    if (!key.length) return YKError(@"invalid argument", @"缺少必填参数: key");

    CCAlgorithm alg = kCCAlgorithmAES;
    size_t block = kCCBlockSizeAES128;
    if ([algo isEqualToString:@"DES"]) { alg = kCCAlgorithmDES; block = kCCBlockSizeDES; }
    else if ([algo isEqualToString:@"3DES"]) { alg = kCCAlgorithm3DES; block = kCCBlockSize3DES; }
    if (iv.length != block) iv = [NSMutableData dataWithLength:block];

    size_t outLen = 0;
    NSMutableData *out = [NSMutableData dataWithLength:data.length + block];
    CCCryptorStatus st = CCCrypt(enc ? kCCEncrypt : kCCDecrypt, alg, kCCOptionPKCS7Padding,
                                 key.bytes, key.length, iv.bytes,
                                 data.bytes, data.length, out.mutableBytes, out.length, &outLen);
    if (st != kCCSuccess) return YKError(@"invalid argument", @"参数错误: base64 长度不合法");
    out.length = outLen;
    return YKValue(@{ @"encoding": @"base64",
                      @"data": [out base64EncodedStringWithOptions:0],
                      @"size": @(out.length) });
}

// GCM：返回 {tag:{encoding,data,size}, cipherData:{…}}（实测结构）
+ (NSDictionary *)gcm:(NSDictionary *)b encrypt:(BOOL)enc {
    NSData *key = YKDataFromAny(b[@"key"], b[@"keyEncoding"]);
    NSData *iv  = YKDataFromAny(b[@"iv"], b[@"keyEncoding"]);
    if (!key.length || iv.length != 12)
        return YKError(@"invalid argument", @"缺少必填参数: key / iv(12B)");

    if (!enc) {
        NSData *cipher = YKDataFromAny(b[@"cipherData"], @"base64");
        NSData *tag = YKDataFromAny(b[@"tag"], @"base64");
        if (!cipher || tag.length != 16) return YKError(@"invalid argument", @"参数错误: base64 长度不合法");
        CCCryptorRef ctx = NULL;
        CCCryptorCreateWithMode(kCCDecrypt, kCCModeGCM, kCCAlgorithmAES, ccNoPadding,
                                iv.bytes, key.bytes, key.length, NULL, 0, 0, 0, &ctx);
        CCCryptorGCMAddIV(ctx, iv.bytes, iv.length);
        NSMutableData *plain = [NSMutableData dataWithLength:cipher.length];
        CCCryptorGCMDecrypt(ctx, cipher.bytes, cipher.length, plain.mutableBytes);
        size_t tagLen = 16;
        CCCryptorStatus vs = CCCryptorGCMFinal(ctx, (void *)tag.bytes, &tagLen);
        CCCryptorRelease(ctx);
        if (vs != kCCSuccess) return YKError(@"invalid argument", @"GCM 校验失败");
        return YKValue(@{ @"encoding": @"utf8",
                          @"data": [[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding] ?:
                                   [plain base64EncodedStringWithOptions:0],
                          @"size": @(plain.length) });
    }

    NSData *plain = YKDataFromAny(b[@"plainData"] ?: b[@"data"], b[@"inputEncoding"] ?: @"utf8");
    if (!plain) return YKError(@"invalid argument", @"缺少必填参数: plainData");
    CCCryptorRef ctx = NULL;
    CCCryptorCreateWithMode(kCCEncrypt, kCCModeGCM, kCCAlgorithmAES, ccNoPadding,
                            iv.bytes, key.bytes, key.length, NULL, 0, 0, 0, &ctx);
    CCCryptorGCMAddIV(ctx, iv.bytes, iv.length);
    size_t outLen = plain.length + 16;
    NSMutableData *cipher = [NSMutableData dataWithLength:outLen];
    CCCryptorGCMEncrypt(ctx, plain.bytes, plain.length, cipher.mutableBytes, &outLen);
    unsigned char tag[16] = {0};
    size_t tagLen = sizeof(tag);
    CCCryptorGCMFinal(ctx, tag, &tagLen);
    CCCryptorRelease(ctx);
    cipher.length = outLen;
    return YKValue(@{ @"tag": @{ @"encoding": @"base64",
                                @"data": [NSData dataWithBytes:tag length:tagLen].base64EncodedStringWithOptions(0),
                                @"size": @(tagLen) },
                      @"cipherData": @{ @"encoding": @"base64",
                                        @"data": [cipher base64EncodedStringWithOptions:0],
                                        @"size": @(cipher.length) } });
}

+ (NSDictionary *)rsa:(NSDictionary *)b encrypt:(BOOL)enc {
    NSData *data = enc ? YKDataFromAny(b[@"plainData"] ?: b[@"data"], b[@"inputEncoding"] ?: @"utf8")
                       : YKDataFromAny(b[@"cipherData"] ?: b[@"data"], @"base64");
    NSString *pem = enc ? (b[@"publicKeyPEM"] ?: b[@"key"]) : (b[@"privateKeyPEM"] ?: b[@"key"]);
    if (!data) return YKError(@"invalid argument", @"缺少必填参数: plainData/cipherData");
    if (![pem isKindOfClass:[NSString class]] || !pem.length)
        return YKError(@"invalid argument", enc ? @"缺少必填参数: publicKeyPEM" : @"缺少必填参数: privateKeyPEM");

    SecKeyRef key = YKSecKeyFromPEM(pem, enc ? kSecAttrKeyClassPublic : kSecAttrKeyClassPrivate);
    if (!key) return YKError(@"invalid argument",
                             [NSString stringWithFormat:@"RSA %@失败: DECODER routines::unsupported",
                              enc ? @"加密" : @"解密"]);
    CFErrorRef err = NULL;
    SecKeyAlgorithm alg = kSecKeyAlgorithmRSAEncryptionPKCS1;
    CFDataRef out = enc ? SecKeyCreateEncryptedData(key, alg, (__bridge CFDataRef)data, &err)
                        : SecKeyCreateDecryptedData(key, alg, (__bridge CFDataRef)data, &err);
    CFRelease(key);
    if (!out) return YKError(@"invalid argument", @"RSA 运算失败");
    NSData *d = (__bridge_transfer NSData *)out;
    return YKValue(@{ @"encoding": @"base64",
                      @"data": [d base64EncodedStringWithOptions:0],
                      @"size": @(d.length) });
}

+ (NSDictionary *)sign:(NSDictionary *)b {
    NSData *data = YKDataFromAny(b[@"data"], b[@"inputEncoding"] ?: @"utf8");
    NSString *pem = b[@"privateKeyPEM"] ?: b[@"key"];
    if (!data) return YKError(@"invalid argument", @"缺少必填参数: data");
    if (![pem isKindOfClass:[NSString class]] || !pem.length)
        return YKError(@"invalid argument", @"缺少必填参数: privateKeyPEM");
    SecKeyRef key = YKSecKeyFromPEM(pem, kSecAttrKeyClassPrivate);
    if (!key) return YKError(@"invalid argument",
                             @"数字签名失败: error:1E08010C:DECODER routines::unsupported");
    CFErrorRef err = NULL;
    CFDataRef sig = SecKeyCreateSignature(key, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,
                                          (__bridge CFDataRef)data, &err);
    CFRelease(key);
    if (!sig) return YKError(@"invalid argument", @"数字签名失败");
    NSData *d = (__bridge_transfer NSData *)sig;
    return YKValue(@{ @"encoding": @"base64",
                      @"data": [d base64EncodedStringWithOptions:0],
                      @"size": @(d.length) });
}

+ (NSDictionary *)verify:(NSDictionary *)b {
    NSData *data = YKDataFromAny(b[@"data"], b[@"inputEncoding"] ?: @"utf8");
    NSData *sig = YKDataFromAny(b[@"signature"], @"base64");
    NSString *pem = b[@"publicKeyPEM"] ?: b[@"key"];
    if (!data || !sig) return YKError(@"invalid argument", @"缺少必填参数: data/signature");
    SecKeyRef key = YKSecKeyFromPEM(pem, kSecAttrKeyClassPublic);
    if (!key) return YKError(@"invalid argument", @"公钥解析失败");
    CFErrorRef err = NULL;
    BOOL ok = SecKeyVerifySignature(key, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,
                                    (__bridge CFDataRef)data, (__bridge CFDataRef)sig, &err);
    CFRelease(key);
    return YKValue(@(ok));
}

+ (NSDictionary *)randomBytes:(NSDictionary *)b {
    NSInteger n = [b[@"length"] integerValue] ?: 16;      // 实测默认 16
    if (n <= 0 || n > 4096) return YKError(@"invalid argument", @"参数错误: length 超出范围");
    NSMutableData *d = [NSMutableData dataWithLength:n];
    if (SecRandomCopyBytes(kSecRandomDefault, n, d.mutableBytes) != errSecSuccess)
        return YKError(@"invalid argument", @"随机数生成失败");
    NSString *enc = b[@"encoding"] ?: @"base64";
    return YKValue(@{ @"encoding": enc, @"data": YKEncodeData(d, enc), @"size": @(n) });
}

+ (NSDictionary *)dispatch:(NSString *)verb body:(NSDictionary *)b {
    if ([verb isEqualToString:@"base64/encode"])   return [self base64Encode:b];
    if ([verb isEqualToString:@"base64/decode"])   return [self base64Decode:b];
    if ([verb isEqualToString:@"hex/encode"])      return [self hexEncode:b];
    if ([verb isEqualToString:@"hex/decode"])      return [self hexDecode:b];
    if ([verb isEqualToString:@"url/encode"])      return [self urlEncode:b];
    if ([verb isEqualToString:@"url/decode"])      return [self urlDecode:b];
    if ([verb isEqualToString:@"digest"])          return [self digest:b];
    if ([verb isEqualToString:@"hmac"])            return [self hmac:b];
    if ([verb isEqualToString:@"pbkdf2"])          return [self pbkdf2:b];
    if ([verb isEqualToString:@"hkdf"])            return [self hkdf:b];
    if ([verb isEqualToString:@"randomBytes"])     return [self randomBytes:b];
    if ([verb isEqualToString:@"encrypt"] || [verb isEqualToString:@"encryptString"]) return [self blockCipher:b encrypt:YES];
    if ([verb isEqualToString:@"decrypt"] || [verb isEqualToString:@"decryptString"]) return [self blockCipher:b encrypt:NO];
    if ([verb isEqualToString:@"gcm/encrypt"])     return [self gcm:b encrypt:YES];
    if ([verb isEqualToString:@"gcm/decrypt"])     return [self gcm:b encrypt:NO];
    if ([verb isEqualToString:@"rsa/encrypt"])     return [self rsa:b encrypt:YES];
    if ([verb isEqualToString:@"rsa/decrypt"])     return [self rsa:b encrypt:NO];
    if ([verb isEqualToString:@"sign"])            return [self sign:b];
    if ([verb isEqualToString:@"verify"])          return [self verify:b];
    return YKError(@"invalid argument", verb);
}
@end

#pragma mark =============== NETWORK（21） ===============

@interface YKNetworkModule : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSURLSessionDataTask *> *tasks;
@property (nonatomic, strong) NSURLSessionConfiguration *config;
@end

@implementation YKNetworkModule

+ (instancetype)shared {
    static YKNetworkModule *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [YKNetworkModule new]; s.tasks = [NSMutableDictionary dictionary];
                            s.config = [NSURLSessionConfiguration defaultSessionConfiguration]; });
    return s;
}

+ (NSDictionary *)request:(NSDictionary *)b method:(NSString *)method {
    NSString *url = b[@"url"];
    if (!url.length) return YKError(@"invalid_argument", @"url 不能为空");
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.HTTPMethod = method;
    req.timeoutInterval = [b[@"timeout"] doubleValue] ?: 30.0;
    NSDictionary *headers = b[@"headers"];
    for (NSString *k in headers) [req setValue:headers[k] forHTTPHeaderField:k];

    if (b[@"json"] && [NSJSONSerialization isValidJSONObject:b[@"json"]]) {
        req.HTTPBody = [NSJSONSerialization dataWithJSONObject:b[@"json"] options:0 error:NULL];
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    } else if (b[@"form"]) {
        NSMutableArray *pairs = [NSMutableArray array];
        for (NSString *k in b[@"form"])
            [pairs addObject:[NSString stringWithFormat:@"%@=%@", k, b[@"form"][k]]];
        req.HTTPBody = [[pairs componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
        [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    } else if (b[@"body"]) {
        req.HTTPBody = [b[@"body"] isKindOfClass:[NSData class]] ? b[@"body"]
                     : [b[@"body"] dataUsingEncoding:NSUTF8StringEncoding];
    }

    __block NSData *body = nil; __block NSInteger code = -1; __block NSError *err = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *t = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            body = d; code = [(NSHTTPURLResponse *)r statusCode]; err = e;
            dispatch_semaphore_signal(sem);
        }];
    [t resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)((req.timeoutInterval + 2) * NSEC_PER_SEC)));
    if (err) return YKError(@"network_error", err.localizedDescription);

    NSString *text = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
    id json = body ? [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL] : nil;
    return YKValue(@{ @"status": @(code),
                      @"headers": @{},
                      @"body": json ?: (text ?: @""),
                      @"size": @(body.length) });
}

+ (NSDictionary *)download:(NSDictionary *)b {
    NSString *url = b[@"url"], *to = b[@"path"] ?: b[@"destinationPath"];
    if (!url.length || !to.length) return YKError(@"invalid_argument", @"url/path 不能为空");
    NSData *d = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
    if (!d) return YKError(@"network_error", @"下载失败");
    BOOL ok = [d writeToFile:to atomically:YES];
    return ok ? YKValue(@{ @"path": to, @"size": @(d.length) })
              : YKError(@"write_failed", @"写入失败");
}

+ (NSDictionary *)upload:(NSDictionary *)b {
    NSString *url = b[@"url"], *path = b[@"path"];
    if (!url.length || !path.length) return YKError(@"invalid_argument", @"url/path 不能为空");
    NSData *file = [NSData dataWithContentsOfFile:path];
    if (!file) return YKError(@"file_not_found", @"文件不存在");
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.HTTPMethod = @"POST";
    NSString *boundary = [[NSUUID UUID] UUIDString];
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]
        forHTTPHeaderField:@"Content-Type"];
    NSMutableData *body = [NSMutableData data];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\n\r\n",
                       boundary, path.lastPathComponent] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:file];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    req.HTTPBody = body;
    __block NSInteger code = -1;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            code = [(NSHTTPURLResponse *)r statusCode]; dispatch_semaphore_signal(sem); }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    return YKValue(@{ @"status": @(code), @"uploaded": @(file.length) });
}

+ (NSDictionary *)cookies {
    NSHTTPCookieStorage *s = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSMutableArray *out = [NSMutableArray array];
    for (NSHTTPCookie *c in s.cookies)
        [out addObject:@{ @"name": c.name, @"value": c.value, @"domain": c.domain,
                          @"path": c.path, @"secure": @(c.isSecure) }];
    return YKValue(out);
}

+ (NSDictionary *)proxy {
    NSDictionary *p = (__bridge_transfer NSDictionary *)
        CFNetworkCopySystemProxySettings();
    return YKValue(p ?: @{});
}
@end

#pragma mark =============== 服务级（http 32）+ 引擎配置（2） ===============

@interface YKServiceModule : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *engineConfig;
@end
@implementation YKServiceModule
+ (instancetype)shared {
    static YKServiceModule *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [YKServiceModule new]; s.engineConfig = [NSMutableDictionary dictionary]; });
    return s;
}
+ (NSDictionary *)engineConfigGet { return YKValue([self shared].engineConfig ?: @{}); }
+ (NSDictionary *)engineConfigSet:(NSDictionary *)b {
    [[self shared].engineConfig addEntriesFromDictionary:b];
    return YKValue([self shared].engineConfig);
}
@end

#pragma mark =============== 路由表（76 条，实测生成） ===============

@interface YKCryptoRouteModule : NSObject
+ (NSArray<NSArray<NSString *> *> *)routesLive;
@end
@implementation YKCryptoRouteModule
+ (NSArray<NSArray<NSString *> *> *)routesLive {
    return @[
        @[@"POST", @"/crypto/base64/encode", @"dispatch:"],
        @[@"POST", @"/crypto/base64/decode", @"dispatch:"],
        @[@"POST", @"/crypto/hex/encode", @"dispatch:"],
        @[@"POST", @"/crypto/hex/decode", @"dispatch:"],
        @[@"POST", @"/crypto/url/encode", @"dispatch:"],
        @[@"POST", @"/crypto/url/decode", @"dispatch:"],
        @[@"POST", @"/crypto/digest", @"dispatch:"],
        @[@"POST", @"/crypto/hmac", @"dispatch:"],
        @[@"POST", @"/crypto/pbkdf2", @"dispatch:"],
        @[@"POST", @"/crypto/hkdf", @"dispatch:"],
        @[@"POST", @"/crypto/randomBytes", @"dispatch:"],
        @[@"POST", @"/crypto/encrypt", @"dispatch:"],
        @[@"POST", @"/crypto/decrypt", @"dispatch:"],
        @[@"POST", @"/crypto/encryptString", @"dispatch:"],
        @[@"POST", @"/crypto/decryptString", @"dispatch:"],
        @[@"POST", @"/crypto/gcm/encrypt", @"dispatch:"],
        @[@"POST", @"/crypto/gcm/decrypt", @"dispatch:"],
        @[@"POST", @"/crypto/rsa/encrypt", @"dispatch:"],
        @[@"POST", @"/crypto/rsa/decrypt", @"dispatch:"],
        @[@"POST", @"/crypto/sign", @"dispatch:"],
        @[@"POST", @"/crypto/verify", @"dispatch:"],
    ];
}
@end

@interface YKNetworkRouteModule : NSObject
+ (NSArray<NSArray<NSString *> *> *)routesLive;
@end
@implementation YKNetworkRouteModule
+ (NSArray<NSArray<NSString *> *> *)routesLive {
    return @[
        @[@"POST",   @"/network/get",                 @"dispatch:"],
        @[@"POST",   @"/network/postJSON",            @"dispatch:"],
        @[@"POST",   @"/network/postForm",            @"dispatch:"],
        @[@"POST",   @"/network/request",             @"dispatch:"],
        @[@"POST",   @"/network/cancel",              @"dispatch:"],
        @[@"POST",   @"/network/upload",              @"dispatch:"],
        @[@"POST",   @"/network/download",            @"dispatch:"],
        @[@"POST",   @"/network/proxy",               @"dispatch:"],
        @[@"GET",    @"/network/proxy",               @"dispatch:"],
        @[@"DELETE", @"/network/proxy",               @"dispatch:"],
        @[@"GET",    @"/network/cookies",             @"dispatch:"],
        @[@"DELETE", @"/network/cookies",             @"dispatch:"],
        @[@"POST",   @"/network/cookie",              @"dispatch:"],
        @[@"GET",    @"/network/cookieStorage",       @"dispatch:"],
        @[@"POST",   @"/network/cookieStorage",       @"dispatch:"],
        @[@"DELETE", @"/network/cookieStorage/file",  @"dispatch:"],
        @[@"POST",   @"/network/cookieStorage/flush", @"dispatch:"],
        @[@"POST",   @"/network/cookieStorage/load",  @"dispatch:"],
        @[@"GET",    @"/network/defaults",            @"dispatch:"],
        @[@"POST",   @"/network/defaults",            @"dispatch:"],
        @[@"POST",   @"/network/defaults/reset",      @"dispatch:"],
    ];
}
@end

@interface YKServiceRouteModule : NSObject
+ (NSArray<NSArray<NSString *> *> *)routesLive;
@end
@implementation YKServiceRouteModule
+ (NSArray<NSArray<NSString *> *> *)routesLive {
    return @[
        @[@"OPTIONS", @"/*",                                  @"handleOptions:"],   // CORS preflight
        @[@"GET",     @"/health",                             @"getHealth:"],
        @[@"GET",     @"/status",                             @"getStatus:"],
        @[@"GET",     @"/routes",                             @"getRoutes:"],
        @[@"POST",    @"/session/create",                     @"handleSessionCreate:"],
        @[@"GET",     @"/session/current",                    @"getSessionCurrent:"],
        @[@"GET",     @"/session/list",                       @"getSessionList:"],
        @[@"GET",     @"/session/status",                     @"getSessionStatus:"],
        @[@"GET",     @"/session/requests",                   @"getSessionRequests:"],
        @[@"POST",    @"/session/pause",                      @"handleSessionPause:"],
        @[@"POST",    @"/session/resume",                     @"handleSessionResume:"],
        @[@"DELETE",  @"/session",                            @"handleSessionDelete:"],
        @[@"DELETE",  @"/session/all",                        @"handleSessionDeleteAll:"],   // CRITICAL
        @[@"GET",     @"/internal/engine/config",             @"getEngineConfig:"],
        @[@"POST",    @"/internal/engine/config",             @"handleEngineConfig:"],
        @[@"GET",     @"/wda/shutdown",                       @"getWdaShutdown:"],           // CRITICAL
        @[@"GET",     @"/executor/scripts",                   @"getExecutorScripts:"],
        @[@"POST",    @"/executor/scripts/delete",            @"handleExecutorScriptDelete:"], // CRITICAL
        @[@"GET",     @"/executor/script-policy",             @"getExecutorPolicy:"],
        @[@"POST",    @"/executor/script-policy",             @"handleExecutorPolicy:"],
        @[@"POST",    @"/executor/script-policy/delete",      @"handleExecutorPolicyDelete:"],
        @[@"POST",    @"/executor/run",                       @"handleExecutorRun:"],         // CRITICAL
        @[@"GET",     @"/executor/runs",                      @"getExecutorRuns:"],
        @[@"GET",     @"/executor/runs/:runId",               @"getExecutorRun:"],
        @[@"GET",     @"/executor/runs/:runId/logs",          @"getExecutorRunLogs:"],
        @[@"GET",     @"/executor/runs/:runId/http-logs",     @"getExecutorRunHTTPLogs:"],
        @[@"GET",     @"/executor/runs/:runId/ui-events",     @"getExecutorRunUIEvents:"],
        @[@"POST",    @"/executor/runs/:runId/pause",         @"handleExecutorRunPause:"],
        @[@"POST",    @"/executor/runs/:runId/resume",        @"handleExecutorRunResume:"],
        @[@"POST",    @"/executor/runs/:runId/stop",          @"handleExecutorRunStop:"],
        @[@"POST",    @"/executor/runs/:runId/rerun",         @"handleExecutorRunRerun:"],
        @[@"POST",    @"/executor/program/install",           @"handleExecutorProgramInstall:"],
        @[@"GET",     @"/executor/program/install/status",    @"getExecutorProgramInstallStatus:"],
        @[@"GET",     @"/executor/program/status",            @"getExecutorProgramStatus:"],
    ];
}
@end
