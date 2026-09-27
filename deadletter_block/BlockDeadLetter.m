/*
 * BlockDeadLetter.dylib — defensive URL rewrite for FomoPeek apptrace
 *
 * Rewrites the Bitbucket dead-drop URL to https://www.baidu.com so apptrace
 * cannot fetch the encrypted C2 list. AES decrypt of the Baidu response will
 * fail, which is intentional (no usable config).
 *
 * Build (needs iOS SDK / Xcode on macOS):
 *   ./build.sh
 *
 * Inject (re-sign IPA / jailbreak insert as appropriate):
 *   insert_dylib --inplace @rpath/BlockDeadLetter.dylib FomoPeek
 *   copy dylib into FomoPeek.app/Frameworks/
 */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static NSString * const kDeadLetterNeedle1 = @"bitbucket.org/discordseven";
static NSString * const kDeadLetterNeedle2 = @"xxhVOn";
static NSString * const kRedirectURL = @"https://www.baidu.com";

static BOOL ATIsDeadLetter(NSString *url) {
    if (url.length == 0) return NO;
    NSString *lower = url.lowercaseString;
    return [lower containsString:kDeadLetterNeedle1.lowercaseString] ||
           [lower containsString:kDeadLetterNeedle2.lowercaseString];
}

static NSString *ATLRewriteIfNeeded(NSString *url) {
    if (!ATIsDeadLetter(url)) return url;
    NSLog(@"[BlockDeadLetter] rewrite %@ -> %@", url, kRedirectURL);
    return kRedirectURL;
}

#pragma mark - Swizzle helpers

static void ATSwizzleClassMethod(Class cls, SEL origSel, SEL newSel) {
    Method orig = class_getClassMethod(cls, origSel);
    Method news = class_getClassMethod(cls, newSel);
    if (!orig || !news) return;
    method_exchangeImplementations(orig, news);
}

static void ATSwizzleInstanceMethod(Class cls, SEL origSel, SEL newSel) {
    Method orig = class_getInstanceMethod(cls, origSel);
    Method news = class_getInstanceMethod(cls, newSel);
    if (!orig || !news) return;
    method_exchangeImplementations(orig, news);
}

#pragma mark - NSURL

@interface NSURL (BlockDeadLetter)
+ (instancetype)bdl_URLWithString:(NSString *)URLString;
+ (instancetype)bdl_URLWithString:(NSString *)URLString relativeToURL:(NSURL *)baseURL;
@end

@implementation NSURL (BlockDeadLetter)

+ (instancetype)bdl_URLWithString:(NSString *)URLString {
    return [self bdl_URLWithString:ATLRewriteIfNeeded(URLString)];
}

+ (instancetype)bdl_URLWithString:(NSString *)URLString relativeToURL:(NSURL *)baseURL {
    return [self bdl_URLWithString:ATLRewriteIfNeeded(URLString) relativeToURL:baseURL];
}

@end

#pragma mark - NSURLRequest / NSMutableURLRequest

@interface NSURLRequest (BlockDeadLetter)
+ (instancetype)bdl_requestWithURL:(NSURL *)URL;
@end

@implementation NSURLRequest (BlockDeadLetter)

+ (instancetype)bdl_requestWithURL:(NSURL *)URL {
    if (ATIsDeadLetter(URL.absoluteString)) {
        URL = [NSURL URLWithString:kRedirectURL];
        NSLog(@"[BlockDeadLetter] requestWithURL rewrite -> %@", kRedirectURL);
    }
    return [self bdl_requestWithURL:URL];
}

@end

@interface NSMutableURLRequest (BlockDeadLetter)
- (void)bdl_setURL:(NSURL *)URL;
@end

@implementation NSMutableURLRequest (BlockDeadLetter)

- (void)bdl_setURL:(NSURL *)URL {
    if (ATIsDeadLetter(URL.absoluteString)) {
        URL = [NSURL URLWithString:kRedirectURL];
        NSLog(@"[BlockDeadLetter] setURL rewrite -> %@", kRedirectURL);
    }
    [self bdl_setURL:URL];
}

@end

#pragma mark - Optional: block raw data download by path (defense in depth)

@interface NSData (BlockDeadLetter)
+ (instancetype)bdl_dataWithContentsOfURL:(NSURL *)url;
+ (instancetype)bdl_dataWithContentsOfURL:(NSURL *)url options:(NSDataReadingOptions)options error:(NSError **)error;
@end

@implementation NSData (BlockDeadLetter)

+ (instancetype)bdl_dataWithContentsOfURL:(NSURL *)url {
    if (ATIsDeadLetter(url.absoluteString)) {
        NSLog(@"[BlockDeadLetter] block dataWithContentsOfURL %@", url);
        url = [NSURL URLWithString:kRedirectURL];
    }
    return [self bdl_dataWithContentsOfURL:url];
}

+ (instancetype)bdl_dataWithContentsOfURL:(NSURL *)url options:(NSDataReadingOptions)options error:(NSError **)error {
    if (ATIsDeadLetter(url.absoluteString)) {
        NSLog(@"[BlockDeadLetter] block dataWithContentsOfURL:options: %@", url);
        url = [NSURL URLWithString:kRedirectURL];
    }
    return [self bdl_dataWithContentsOfURL:url options:options error:error];
}

@end

__attribute__((constructor))
static void BlockDeadLetterInit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ATSwizzleClassMethod(object_getClass([NSURL class]),
                              @selector(URLWithString:),
                              @selector(bdl_URLWithString:));
        ATSwizzleClassMethod(object_getClass([NSURL class]),
                              @selector(URLWithString:relativeToURL:),
                              @selector(bdl_URLWithString:relativeToURL:));
        ATSwizzleClassMethod(object_getClass([NSURLRequest class]),
                              @selector(requestWithURL:),
                              @selector(bdl_requestWithURL:));
        ATSwizzleInstanceMethod([NSMutableURLRequest class],
                                  @selector(setURL:),
                                  @selector(bdl_setURL:));
        ATSwizzleClassMethod(object_getClass([NSData class]),
                              @selector(dataWithContentsOfURL:),
                              @selector(bdl_dataWithContentsOfURL:));
        ATSwizzleClassMethod(object_getClass([NSData class]),
                              @selector(dataWithContentsOfURL:options:error:),
                              @selector(bdl_dataWithContentsOfURL:options:error:));

        NSLog(@"[BlockDeadLetter] installed — dead-drop URLs rewrite to %@", kRedirectURL);
    });
}
