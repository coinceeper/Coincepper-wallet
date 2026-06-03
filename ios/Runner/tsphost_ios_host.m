#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <UIKit/UIKit.h>
#import <math.h>
#include <stdlib.h>

void tsphost_ios_free_str(char *p) { free(p); }

static char *TsphResultJSON(BOOL success, NSString *err, NSString *target, NSString *furl, int sc,
    long long resMs, long long totMs, NSString *ua) {
  NSString *finalU = furl.length > 0 ? furl : target;
  NSDictionary *d = @{
    @"success" : @(success),
    @"error_msg" : err ?: @"",
    @"target_url" : target ?: @"",
    @"final_url" : finalU ?: @"",
    @"status_code" : @(sc),
    @"response_time_ms" : @(resMs),
    @"total_time_ms" : @(totMs),
    @"user_agent" : ua ?: @""
  };
  NSData *b = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
  if (!b) {
    return strdup("{\"success\":false,\"error_msg\":\"json\"}");
  }
  return strdup([[NSString alloc] initWithData:b encoding:NSUTF8StringEncoding].UTF8String);
}

static char *TsphErr(NSString *msg, NSString *target) {
  return TsphResultJSON(NO, msg, target, target, 0, 0, 0, @"");
}

static UIWindow *TsphKeyWindow(void) {
  for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
    if (![sc isKindOfClass:[UIWindowScene class]]) {
      continue;
    }
    UIWindowScene *wsc = (UIWindowScene *)sc;
    for (UIWindow *w in wsc.windows) {
      if (w.isKeyWindow) {
        return w;
      }
    }
    if (wsc.windows.count) {
      return wsc.windows.firstObject;
    }
  }
  return [UIApplication sharedApplication].keyWindow;
}

static int TsphRandBetween(int a, int b) {
  if (b < a) {
    int t = a;
    a = b;
    b = t;
  }
  if (a == b) {
    return a;
  }
  return a + (int)arc4random_uniform((u_int32_t)(b - a + 1));
}

/// Ends a UIKit background task if still active (safe to call multiple times).
static void TsphEndBackgroundTask(UIBackgroundTaskIdentifier *taskID) {
  if (!taskID || *taskID == UIBackgroundTaskInvalid) {
    return;
  }
  UIBackgroundTaskIdentifier t = *taskID;
  *taskID = UIBackgroundTaskInvalid;
  [[UIApplication sharedApplication] endBackgroundTask:t];
}

static NSString *TsphUnquote(NSString *raw) {
  if (raw == nil) {
    return @"";
  }
  NSString *t = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (t.length >= 2 && [t hasPrefix:@"\""] && [t hasSuffix:@"\""]) {
    t = [t substringWithRange:NSMakeRange(1, t.length - 2)];
  }
  return t;
}

@interface TspHNav : NSObject <WKNavigationDelegate>
@property (nonatomic) NSDate *t0;
@property (nonatomic) NSDate *tLoad0;
@property (nonatomic) NSString *target;
@property (nonatomic) int statusG;
@property (nonatomic) int failed;
@property (nonatomic) NSString *failMsg;
@property (nonatomic) NSTimeInterval deadline;
@property (nonatomic) int scrollN;
@property (nonatomic) int dwellMs;
@property (nonatomic) dispatch_semaphore_t sem;
// strdup'd C string; void* to satisfy ARC
@property (nonatomic) void *outC;
@property (nonatomic) WKWebView *wv;
@end

@implementation TspHNav

- (void)navigateDidFail {
  if (self.outC) {
    return;
  }
  if (self.wv) {
    [self.wv stopLoading];
    [self.wv setNavigationDelegate:nil];
    [self.wv removeFromSuperview];
    self.wv = nil;
  }
  self.outC = (void *)TsphErr(self.failMsg.length ? self.failMsg : @"nav_error", self.target);
  dispatch_semaphore_signal(self.sem);
}

- (void)completeSuccess:(NSString *)furl {
  if (self.outC) {
    return;
  }
  NSDate *tEnd = [NSDate date];
  NSTimeInterval startE = [self.t0 timeIntervalSince1970];
  long long totMs2 = (long long)(([tEnd timeIntervalSince1970] - startE) * 1000.0);
  long long resMs2 = 0;
  if (self.tLoad0) {
    resMs2 = (long long)([tEnd timeIntervalSinceDate:self.tLoad0] * 1000.0);
  }
  int sc = self.statusG;
  if (sc <= 0) {
    sc = 200;
  }
  [self.wv stopLoading];
  __weak TspHNav *wk = self;
  NSString *fa0 = furl.length > 0 ? furl : self.target;
  [self
      evaluateUAFinal:^(NSString *ua) {
        TspHNav *s = wk;
        if (s == nil || s.outC) {
          return;
        }
        s.outC = (void *)TsphResultJSON(YES, @"", s.target, fa0, sc, resMs2, totMs2, ua);
        if (s.wv) {
          [s.wv setNavigationDelegate:nil];
          [s.wv removeFromSuperview];
        }
        s.wv = nil;
        dispatch_semaphore_signal(s.sem);
      }];
}

- (void)evaluateUAFinal:(void (^)(NSString *))done {
  __weak typeof(self) wself = self;
  [self.wv
      evaluateJavaScript:@"(function(){ return String(navigator.userAgent); })();"
         completionHandler:^(id _Nullable r, NSError *_Nullable e) {
           (void)e;
           NSString *ua = @"";
           if ([r isKindOfClass:[NSString class]]) {
             ua = TsphUnquote((NSString *)r);
           } else {
             if (wself.wv != nil) {
               ua = wself.wv.customUserAgent ?: @"";
             }
           }
           done(ua);
         }];
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)n {
  (void)n;
  (void)webView;
  if (self.tLoad0 == nil) {
    self.tLoad0 = [NSDate date];
  }
}

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationResponse:(WKNavigationResponse *)response
    decisionHandler:(void (^)(WKNavigationResponsePolicy))d {
  if (response.response && [response.response isKindOfClass:[NSHTTPURLResponse class]]) {
    self.statusG = (int)[(NSHTTPURLResponse *)response.response statusCode];
  }
  d(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)n withError:(NSError *)e {
  (void)n;
  (void)webView;
  self.failMsg = e.localizedDescription ?: @"fail_prov";
  self.failed = 1;
  [self navigateDidFail];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)n withError:(NSError *)e {
  (void)webView;
  (void)n;
  if (e.code == NSURLErrorCancelled) {
    return;
  }
  self.failMsg = e.localizedDescription ?: @"fail_nav";
  self.failed = 1;
  [self navigateDidFail];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)n {
  (void)n;
  (void)webView;
  if (self.failed) {
    return;
  }
  NSDate *tNavEnd = [NSDate date];
  long long resMs0 = 0;
  if (self.tLoad0) {
    resMs0 = (long long)([tNavEnd timeIntervalSinceDate:self.tLoad0] * 1000.0);
  }
  (void)resMs0; // for scroll+dwell, total is measured in completeSuccess
  int sn = self.scrollN;
  NSString *scrollJs;
  if (sn <= 0) {
    scrollJs = @"(function(){ return true; })()";
  } else {
    scrollJs = [NSString
        stringWithFormat:
            @"(function(){"
             "var t=0,s=0,m=%d,h=300;"
             "var id=setInterval(function(){"
             "t+=h;s++;window.scrollTo(0,t);if(s>=m)clearInterval(id);"
             "}, 60);"
             "return true;"
             "})()",
        sn];
  }
  NSTimeInterval afterScroll = 0.12 * fmin(4, fmax(1, sn)) + 0.03;
  __weak typeof(self) wself = self;
  [self.wv
      evaluateJavaScript:scrollJs
         completionHandler:^(id _Nullable o, NSError *_Nullable e) {
           (void)o;
           (void)e;
           dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(afterScroll * NSEC_PER_SEC)),
               dispatch_get_main_queue(), ^{
                 TspHNav *s = wself;
                 if (!s || s.outC != NULL) {
                   return;
                 }
                 NSTimeInterval dTime = s.deadline - [NSDate date].timeIntervalSince1970;
                 if (dTime < 0) {
                   dTime = 0;
                 }
                 NSTimeInterval dUse = fmin((NSTimeInterval)s.dwellMs / 1000.0, dTime);
                 [s.wv
                     evaluateJavaScript:
                         @"(function(){ return String(document.location.href); })();"
                        completionHandler:^(id _Nullable u, NSError *_Nullable er) {
                          (void)er;
                          NSString *fu = s.target;
                          if ([u isKindOfClass:[NSString class]]) {
                            fu = TsphUnquote((NSString *)u);
                            if (fu.length == 0) {
                              fu = s.target;
                            }
                          }
                          NSString *ff = fu;
                          dispatch_after(
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(dUse * NSEC_PER_SEC)),
                              dispatch_get_main_queue(), ^{ [s completeSuccess:ff]; });
                        }];
               });
         }];
}
@end

char *tsphost_ios_host_run_web_click(const char *cUrl, const char *cConfig, int timeoutSec) {
  if (!cUrl || cUrl[0] == 0) {
    return TsphErr(@"empty_url", @"");
  }
  NSString *sUrl = [NSString stringWithUTF8String:cUrl];
  NSData *cfgD = cConfig
      ? [[NSString stringWithUTF8String:cConfig] dataUsingEncoding:NSUTF8StringEncoding]
      : [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *cfg = [NSJSONSerialization JSONObjectWithData:cfgD options:0 error:nil];
  if (![cfg isKindOfClass:[NSDictionary class]]) {
    cfg = @{};
  }
  int preMin = (int)[[cfg objectForKey:@"pre_click_min_ms"] intValue];
  if (preMin < 0) {
    preMin = 0;
  }
  int preMax = (int)[[cfg objectForKey:@"pre_click_max_ms"] intValue];
  if (preMax < preMin) {
    preMax = preMin;
  }
  int preMs = (preMax == preMin) ? preMin : TsphRandBetween(preMin, preMax);
  int dMin = (int)[[cfg objectForKey:@"dwell_min_ms"] intValue];
  if (dMin < 0) {
    dMin = 0;
  }
  int dMax = (int)[[cfg objectForKey:@"dwell_max_ms"] intValue];
  if (dMax < dMin) {
    dMax = dMin;
  }
  int dwell = (dMax == dMin) ? dMin : TsphRandBetween(dMin, dMax);
  int scrollN = (int)[[cfg objectForKey:@"scroll_steps"] intValue];
  if (scrollN < 0) {
    scrollN = 0;
  }
  if (scrollN > 12) {
    scrollN = 12;
  }
  NSString *uacfg = [cfg objectForKey:@"user_agent"];
  if (![uacfg isKindOfClass:[NSString class]] || uacfg.length == 0) {
    uacfg = nil;
  }
  NSString *accept = [cfg objectForKey:@"accept_language"];
  if (![accept isKindOfClass:[NSString class]] || accept.length == 0) {
    accept = @"en-US,en;q=0.9";
  }
  __block TspHNav *nav = [TspHNav new];
  NSDate *t0 = [NSDate date];
  nav.t0 = t0;
  nav.tLoad0 = nil;
  nav.target = sUrl;
  nav.statusG = 0;
  nav.dwellMs = dwell;
  nav.scrollN = scrollN;
  nav.deadline = t0.timeIntervalSince1970 + fmax(1, timeoutSec);
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  nav.sem = sem;

  // Extend runtime while user backgrounds the app during a click (~30s typical).
  __block UIBackgroundTaskIdentifier bgTask = UIBackgroundTaskInvalid;
  bgTask = [[UIApplication sharedApplication]
      beginBackgroundTaskWithName:@"com.coinceeper.tsphost.webclick"
                expirationHandler:^{
                  // Runs on the main thread; tear down WKWebView before the task ends.
                  TspHNav *h = nav;
                  if (h && !h.outC) {
                    h.failMsg = @"background_time_expired";
                    [h navigateDidFail];
                  }
                  TsphEndBackgroundTask(&bgTask);
                }];

  dispatch_async(dispatch_get_main_queue(), ^{
    TspHNav *H = nav;
    if (H.outC) {
      return;
    }
    NSTimeInterval nowE = [NSDate date].timeIntervalSince1970;
    if (nowE > H.deadline) {
      H.outC = (void *)TsphErr(@"deadline", sUrl);
      dispatch_semaphore_signal(sem);
      return;
    }
    UIWindow *win = TsphKeyWindow();
    if (!win || !win.rootViewController || !win.rootViewController.view) {
      H.outC = (void *)TsphErr(@"no_key_window", sUrl);
      dispatch_semaphore_signal(sem);
      return;
    }
    UIView *hostV = win.rootViewController.view;
    WKWebViewConfiguration *wconf = [WKWebViewConfiguration new];
    WKWebView *wv = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 1, 1) configuration:wconf];
    wv.hidden = YES;
    wv.allowsBackForwardNavigationGestures = NO;
    if (uacfg) {
      wv.customUserAgent = uacfg;
    }
    wv.translatesAutoresizingMaskIntoConstraints = NO;
    [hostV addSubview:wv];
    if (@available(iOS 11.0, *)) {
      wv.insetsLayoutMarginsFromSafeArea = NO;
      [NSLayoutConstraint activateConstraints:@[
        [wv.widthAnchor constraintEqualToConstant:1],
        [wv.heightAnchor constraintEqualToConstant:1],
        [wv.trailingAnchor constraintEqualToAnchor:hostV.safeAreaLayoutGuide.trailingAnchor],
        [wv.bottomAnchor constraintEqualToAnchor:hostV.safeAreaLayoutGuide.bottomAnchor]
      ]];
    } else {
      wv.frame = CGRectMake(0, 0, 1, 1);
    }
    H.wv = wv;
    wv.navigationDelegate = H;
    NSTimeInterval preS = fmax(0, preMs / 1000.0);
    NSTimeInterval tLeft = H.deadline - [NSDate date].timeIntervalSince1970;
    NSTimeInterval preUse = fmin(preS, fmax(0, tLeft - 0.05));
    __weak TspHNav *wH = H;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(preUse * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      TspHNav *X = wH;
      if (!X || X.outC) {
        return;
      }
      if ([NSDate date].timeIntervalSince1970 > X.deadline) {
        [X.wv setNavigationDelegate:nil];
        [X.wv stopLoading];
        [X.wv removeFromSuperview];
        X.wv = nil;
        X.outC = (void *)TsphErr(@"pre_deadline", sUrl);
        dispatch_semaphore_signal(sem);
        return;
      }
      NSURL *u2 = [NSURL URLWithString:sUrl];
      if (!u2) {
        [X.wv setNavigationDelegate:nil];
        [X.wv stopLoading];
        [X.wv removeFromSuperview];
        X.wv = nil;
        X.outC = (void *)TsphErr(@"bad_url", sUrl);
        dispatch_semaphore_signal(sem);
        return;
      }
      NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:u2];
      [r setValue:accept forHTTPHeaderField:@"Accept-Language"];
      X.tLoad0 = nil;
      [X.wv loadRequest:r];
    });
  });

  long waitNs = (long long)(fmax(3, (double)timeoutSec + 12) * 1e9);
  if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, waitNs)) != 0) {
    void (^teardown)(void) = ^{
      TspHNav *h = nav;
      if (!h) {
        return;
      }
      if (h.wv) {
        [h.wv stopLoading];
        [h.wv setNavigationDelegate:nil];
        [h.wv removeFromSuperview];
        h.wv = nil;
      }
    };
    if ([NSThread isMainThread]) {
      teardown();
    } else {
      dispatch_sync(dispatch_get_main_queue(), teardown);
    }
    TsphEndBackgroundTask(&bgTask);
    return TsphErr(@"wait_timeout", sUrl);
  }
  if (!nav.outC) {
    TsphEndBackgroundTask(&bgTask);
    return TsphErr(@"no_result", sUrl);
  }
  char *out = (char *)nav.outC;
  TsphEndBackgroundTask(&bgTask);
  return out;
}
