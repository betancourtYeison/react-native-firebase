/**
 * Copyright (c) 2016-present Invertase Limited & Contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this library except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

#import <objc/runtime.h>
#import <Firebase/Firebase.h>
#import <GoogleUtilities/GULAppDelegateSwizzler.h>

#import <React/RCTConvert.h>
#import <RNFBApp/RNFBSharedUtils.h>
#import <RNFBApp/RNFBRCTEventEmitter.h>

#import "RNFBMessagingSerializer.h"
#import "RNFBMessaging+AppDelegate.h"

@implementation RNFBMessagingAppDelegate

+ (instancetype)sharedInstance {
  static dispatch_once_t once;
  __strong static RNFBMessagingAppDelegate *sharedInstance;
  dispatch_once(&once, ^{
    sharedInstance = [[RNFBMessagingAppDelegate alloc] init];
  });
  return sharedInstance;
}

- (void)observe {
  static dispatch_once_t once;
  __weak RNFBMessagingAppDelegate *weakSelf = self;
  dispatch_once(&once, ^{
    RNFBMessagingAppDelegate *strongSelf = weakSelf;

    [GULAppDelegateSwizzler registerAppDelegateInterceptor:strongSelf];
    [GULAppDelegateSwizzler proxyOriginalDelegateIncludingAPNSMethods];

    SEL didReceiveRemoteNotificationWithCompletionSEL =
        NSSelectorFromString(@"application:didReceiveRemoteNotification:fetchCompletionHandler:");
    if ([[GULAppDelegateSwizzler sharedApplication].delegate respondsToSelector:didReceiveRemoteNotificationWithCompletionSEL]) {
      // noop - user has own implementation of this method in their AppDelegate, this
      // means GULAppDelegateSwizzler will have already replaced it with a donor method
    } else {
      // add our own donor implementation of application:didReceiveRemoteNotification:fetchCompletionHandler:
      Method donorMethod = class_getInstanceMethod(
          object_getClass(strongSelf), didReceiveRemoteNotificationWithCompletionSEL
      );
      class_addMethod(
          object_getClass([GULAppDelegateSwizzler sharedApplication].delegate),
          didReceiveRemoteNotificationWithCompletionSEL,
          method_getImplementation(donorMethod),
          method_getTypeEncoding(donorMethod)
      );
    }
  });
}

// used to temporarily store a promise instance to resolve calls to `registerForRemoteNotifications`
- (void)setPromiseResolve:(RCTPromiseResolveBlock)resolve andPromiseReject:(RCTPromiseRejectBlock)reject {
  _registerPromiseResolver = resolve;
  _registerPromiseRejecter = reject;
}

#pragma mark -
#pragma mark AppDelegate Methods

// called when `registerForRemoteNotifications` completes successfully
- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
#ifdef DEBUG
  [[FIRMessaging messaging] setAPNSToken:deviceToken type:FIRMessagingAPNSTokenTypeSandbox];
#else
  [[FIRMessaging messaging] setAPNSToken:deviceToken type:FIRMessagingAPNSTokenTypeProd];
#endif

  if (_registerPromiseResolver != nil) {
    _registerPromiseResolver(@([RCTConvert BOOL:@([UIApplication sharedApplication].isRegisteredForRemoteNotifications)]));
    _registerPromiseResolver = nil;
    _registerPromiseRejecter = nil;
  }
}

// called when `registerForRemoteNotifications` fails to complete
- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
  if (_registerPromiseRejecter != nil) {
    [RNFBSharedUtils rejectPromiseWithNSError:_registerPromiseRejecter error:error];
    _registerPromiseResolver = nil;
    _registerPromiseRejecter = nil;
  }
}

@end
