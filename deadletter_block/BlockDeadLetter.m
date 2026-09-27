/*
 * BlockDeadLetter.dylib — force apptrace dead-drop URL to baidu.com
 *
 * apptrace keeps the Bitbucket mailbox URL obfuscated in __DATA (no plaintext
 * export to patch). At runtime it deobfuscates → NSString/NSURL →
 * NSURLConnection sendSynchronousRequest.
 *
 * Strategy (not "guess every request API"):
 *   1) Rewrite the mailbox string as soon as plaintext appears (NSString).
 *   2) Choke the one send API apptrace actually uses (sendSynchronousRequest).
 *   3) NSURL construction as a thin backup.
 *
 * Build:  ./build.sh
 * Inject: insert_dylib --inplace @rpath/BlockDeadLetter.dylib FomoPeek
 */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <string.h>

static NSString * const kRedirectURL = @"https://www.baidu.com";
static const char * const kNeedle1 = "bitbucket.org/discordseven";
static const char * const kNeedle2 = "xxhvon"; /* lower for cmp */

static BOOL ATCstrHasNeedle(const char *s, size_t n, const char *needle) {
    if (!s || !needle || n == 0) return NO;
    size_t nlen = strlen(needle);
    if (nlen == 0 || n < nlen) return NO;
    for (size_t i = 0; i + nlen <= n; i++) {
        size_t j = 0;
        for (; j < nlen; j++) {
            char c = s[i + j];
            if (c >= 'A' && c <= 'Z') c = (char)(c - 'A' + 'a');
            if (c != needle[j]) break;
        }
        if (j == nlen) return YES;
    }
    return NO;
}

static BOOL ATIsDeadLetterCStr(const char *s, size_t n) {
    if (!s) return NO;
    if (n == 0) n = strlen(s);
    return ATCstrHasNeedle(s, n, kNeedle1) || ATCstrHasNeedle(s, n, kNeedle2);
}

static BOOL ATIsDeadLetter(NSString *url) {
    if (url.length == 0) return NO;
    const char *u = url.UTF8String;
    return u && ATIsDeadLetterCStr(u, strlen(u));
}

static BOOL ATCallerInAppTrace(void) {
    Dl_info info;
    /* LR at IMP entry is usually the ObjC caller (apptrace), not msgSend. */
    if (!dladdr(__builtin_return_address(0), &info) || !info.dli_fname)
        return NO;
    return strstr(info.dli_fname, "apptrace.framework/apptrace") != NULL;
}

#pragma mark - Swizzle helpers

static void ATSwizzleClassMethod(Class cls, SEL origSel, SEL newSel) {
    Method orig = class_getClassMethod(cls, origSel);
    Method news = class_getClassMethod(cls, newSel);
    if (!orig || !news) {
        NSLog(@"[BlockDeadLetter] swizzle class fail %@ %@",
              NSStringFromSelector(origSel), cls ? NSStringFromClass(cls) : @"nil");
        return;
    }
    method_exchangeImplementations(orig, news);
}

static void ATSwizzleInstanceMethod(Class cls, SEL origSel, SEL newSel) {
    Method orig = class_getInstanceMethod(cls, origSel);
    Method news = class_getInstanceMethod(cls, newSel);
    if (!orig || !news) {
        NSLog(@"[BlockDeadLetter] swizzle inst fail %@ %@",
              NSStringFromSelector(origSel), cls ? NSStringFromClass(cls) : @"nil");
        return;
    }
    method_exchangeImplementations(orig, news);
}

#pragma mark - NSString: force mailbox address at deobfuscation boundary

@interface NSString (BlockDeadLetter)
+ (instancetype)bdl_stringWithUTF8String:(const char *)nullTerminatedCString;
- (instancetype)bdl_initWithBytes:(const void *)bytes
                           length:(NSUInteger)len
                         encoding:(NSStringEncoding)encoding;
- (instancetype)bdl_initWithData:(NSData *)data encoding:(NSStringEncoding)encoding;
@end

@implementation NSString (BlockDeadLetter)

+ (instancetype)bdl_stringWithUTF8String:(const char *)nullTerminatedCString {
    if (ATIsDeadLetterCStr(nullTerminatedCString, 0)) {
        NSLog(@"[BlockDeadLetter] stringWithUTF8String mailbox -> %@ (apptrace=%d)",
              kRedirectURL, ATCallerInAppTrace());
        return [self bdl_stringWithUTF8String:kRedirectURL.UTF8String];
    }
    return [self bdl_stringWithUTF8String:nullTerminatedCString];
}

- (instancetype)bdl_initWithBytes:(const void *)bytes
                           length:(NSUInteger)len
                         encoding:(NSStringEncoding)encoding {
    if (bytes && len > 0 &&
        (encoding == NSUTF8StringEncoding || encoding == NSASCIIStringEncoding ||
         encoding == NSISOLatin1StringEncoding) &&
        ATIsDeadLetterCStr((const char *)bytes, (size_t)len)) {
        NSLog(@"[BlockDeadLetter] initWithBytes mailbox -> %@", kRedirectURL);
        const char *r = kRedirectURL.UTF8String;
        return [self bdl_initWithBytes:r length:strlen(r) encoding:NSUTF8StringEncoding];
    }
    return [self bdl_initWithBytes:bytes length:len encoding:encoding];
}

- (instancetype)bdl_initWithData:(NSData *)data encoding:(NSStringEncoding)encoding {
    if (data.length > 0 &&
        (encoding == NSUTF8StringEncoding || encoding == NSASCIIStringEncoding) &&
        ATIsDeadLetterCStr((const char *)data.bytes, (size_t)data.length)) {
        NSLog(@"[BlockDeadLetter] initWithData mailbox -> %@", kRedirectURL);
        data = [kRedirectURL dataUsingEncoding:NSUTF8StringEncoding];
        encoding = NSUTF8StringEncoding;
    }
    return [self bdl_initWithData:data encoding:encoding];
}

@end

#pragma mark - NSURL

@interface NSURL (BlockDeadLetter)
+ (instancetype)bdl_URLWithString:(NSString *)URLString;
+ (instancetype)bdl_URLWithString:(NSString *)URLString relativeToURL:(NSURL *)baseURL;
- (instancetype)bdl_initWithString:(NSString *)URLString;
@end

@implementation NSURL (BlockDeadLetter)

+ (instancetype)bdl_URLWithString:(NSString *)URLString {
    if (ATIsDeadLetter(URLString)) {
        NSLog(@"[BlockDeadLetter] URLWithString mailbox -> %@", kRedirectURL);
        URLString = kRedirectURL;
    }
    return [self bdl_URLWithString:URLString];
}

+ (instancetype)bdl_URLWithString:(NSString *)URLString relativeToURL:(NSURL *)baseURL {
    if (ATIsDeadLetter(URLString)) {
        NSLog(@"[BlockDeadLetter] URLWithString:relative mailbox -> %@", kRedirectURL);
        URLString = kRedirectURL;
    }
    return [self bdl_URLWithString:URLString relativeToURL:baseURL];
}

- (instancetype)bdl_initWithString:(NSString *)URLString {
    if (ATIsDeadLetter(URLString)) {
        NSLog(@"[BlockDeadLetter] initWithString mailbox -> %@", kRedirectURL);
        URLString = kRedirectURL;
    }
    return [self bdl_initWithString:URLString];
}

@end

#pragma mark - NSURLConnection: apptrace's real send path

@interface NSURLConnection (BlockDeadLetter)
+ (NSData *)bdl_sendSynchronousRequest:(NSURLRequest *)request
                     returningResponse:(NSURLResponse **)response
                                 error:(NSError **)error;
@end

@implementation NSURLConnection (BlockDeadLetter)

+ (NSData *)bdl_sendSynchronousRequest:(NSURLRequest *)request
                     returningResponse:(NSURLResponse **)response
                                 error:(NSError **)error {
    NSString *url = request.URL.absoluteString;
    if (ATIsDeadLetter(url)) {
        NSLog(@"[BlockDeadLetter] sendSynchronousRequest mailbox -> %@ (was %@)",
              kRedirectURL, url);
        NSMutableURLRequest *rewritten = [request mutableCopy];
        rewritten.URL = [NSURL URLWithString:kRedirectURL];
        request = rewritten;
    }
    return [self bdl_sendSynchronousRequest:request
                          returningResponse:response
                                      error:error];
}

@end

__attribute__((constructor(101)))
static void BlockDeadLetterInit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class nsstringMeta = object_getClass([NSString class]);
        ATSwizzleClassMethod(nsstringMeta,
                             @selector(stringWithUTF8String:),
                             @selector(bdl_stringWithUTF8String:));
        ATSwizzleInstanceMethod([NSString class],
                                @selector(initWithBytes:length:encoding:),
                                @selector(bdl_initWithBytes:length:encoding:));
        ATSwizzleInstanceMethod([NSString class],
                                @selector(initWithData:encoding:),
                                @selector(bdl_initWithData:encoding:));

        Class nsurlMeta = object_getClass([NSURL class]);
        ATSwizzleClassMethod(nsurlMeta,
                             @selector(URLWithString:),
                             @selector(bdl_URLWithString:));
        ATSwizzleClassMethod(nsurlMeta,
                             @selector(URLWithString:relativeToURL:),
                             @selector(bdl_URLWithString:relativeToURL:));
        ATSwizzleInstanceMethod([NSURL class],
                                @selector(initWithString:),
                                @selector(bdl_initWithString:));

        ATSwizzleClassMethod(object_getClass([NSURLConnection class]),
                             @selector(sendSynchronousRequest:returningResponse:error:),
                             @selector(bdl_sendSynchronousRequest:returningResponse:error:));

        NSLog(@"[BlockDeadLetter] installed — mailbox forced to %@", kRedirectURL);
    });
}
