#import "SafePluginRegistry.h"
#import <stdatomic.h>

static atomic_bool gEngineStopping = ATOMIC_VAR_INIT(false);

@implementation THLAppLifecycleGuard

+ (BOOL)isEngineStopping {
  return atomic_load_explicit(&gEngineStopping, memory_order_acquire);
}

+ (void)markEngineStopping {
  atomic_store_explicit(&gEngineStopping, true, memory_order_release);
}

+ (void)markEngineActive {
  atomic_store_explicit(&gEngineStopping, false, memory_order_release);
}

@end

@implementation SafeBinaryMessengerProxy

- (instancetype)initWithTarget:(NSObject<FlutterBinaryMessenger>*)target {
  self = [super init];
  if (self != nil) {
    _target = target;
  }
  return self;
}

- (BOOL)respondsToSelector:(SEL)aSelector {
  if (aSelector == @selector(makeBackgroundTaskQueue) ||
      aSelector == @selector(setMessageHandlerOnChannel:binaryMessageHandler:taskQueue:)) {
    return [_target respondsToSelector:aSelector];
  }
  return [super respondsToSelector:aSelector];
}

- (void)invokeReplySafely:(FlutterBinaryReply _Nullable)callback withData:(NSData* _Nullable)data {
  if (callback == nil) {
    return;
  }
  if ([NSThread isMainThread]) {
    callback(data);
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    callback(data);
  });
}

- (void)sendOnChannelOnMainThread:(NSString*)channel
                          message:(NSData* _Nullable)message
                      binaryReply:(FlutterBinaryReply _Nullable)callback
                        withReply:(BOOL)withReply {
  if ([THLAppLifecycleGuard isEngineStopping]) {
    if (withReply) {
      [self invokeReplySafely:callback withData:nil];
    }
    return;
  }

  @try {
    if (withReply) {
      [_target sendOnChannel:channel message:message binaryReply:callback];
    } else {
      [_target sendOnChannel:channel message:message];
    }
  } @catch (NSException* exception) {
    if (withReply) {
      [self invokeReplySafely:callback withData:nil];
    }
  }
}

- (void)sendOnChannel:(NSString*)channel message:(NSData* _Nullable)message {
  if ([THLAppLifecycleGuard isEngineStopping]) {
    return;
  }
  if ([NSThread isMainThread]) {
    [self sendOnChannelOnMainThread:channel message:message binaryReply:nil withReply:NO];
    return;
  }
  NSString* channelCopy = [channel copy];
  NSData* messageCopy = [message copy];
  dispatch_async(dispatch_get_main_queue(), ^{
    [self sendOnChannelOnMainThread:channelCopy message:messageCopy binaryReply:nil withReply:NO];
  });
}

- (void)sendOnChannel:(NSString*)channel
              message:(NSData* _Nullable)message
          binaryReply:(FlutterBinaryReply _Nullable)callback {
  if ([THLAppLifecycleGuard isEngineStopping]) {
    [self invokeReplySafely:callback withData:nil];
    return;
  }
  if ([NSThread isMainThread]) {
    [self sendOnChannelOnMainThread:channel message:message binaryReply:callback withReply:YES];
    return;
  }
  NSString* channelCopy = [channel copy];
  NSData* messageCopy = [message copy];
  FlutterBinaryReply callbackCopy = [callback copy];
  dispatch_async(dispatch_get_main_queue(), ^{
    [self sendOnChannelOnMainThread:channelCopy
                            message:messageCopy
                        binaryReply:callbackCopy
                          withReply:YES];
  });
}

- (FlutterBinaryMessengerConnection)setMessageHandlerOnChannel:(NSString*)channel
                                          binaryMessageHandler:
                                              (FlutterBinaryMessageHandler _Nullable)handler {
  return [_target setMessageHandlerOnChannel:channel binaryMessageHandler:handler];
}

- (void)cleanUpConnection:(FlutterBinaryMessengerConnection)connection {
  @try {
    [_target cleanUpConnection:connection];
  } @catch (NSException* exception) {
  }
}

- (NSObject<FlutterTaskQueue>*)makeBackgroundTaskQueue {
  return [_target makeBackgroundTaskQueue];
}

- (FlutterBinaryMessengerConnection)
    setMessageHandlerOnChannel:(NSString*)channel
          binaryMessageHandler:(FlutterBinaryMessageHandler _Nullable)handler
                     taskQueue:(NSObject<FlutterTaskQueue>* _Nullable)taskQueue {
  return [_target setMessageHandlerOnChannel:channel
                        binaryMessageHandler:handler
                                   taskQueue:taskQueue];
}

@end

@interface SafePluginRegistrar ()

@property(nonatomic, strong, readonly) SafeBinaryMessengerProxy* messengerProxy;

@end

@implementation SafePluginRegistrar

- (instancetype)initWithTarget:(NSObject<FlutterPluginRegistrar>*)target
     disableLifecycleDelegates:(BOOL)disableLifecycleDelegates {
  self = [super init];
  if (self != nil) {
    _target = target;
    _disableLifecycleDelegates = disableLifecycleDelegates;
    _messengerProxy = [[SafeBinaryMessengerProxy alloc] initWithTarget:[target messenger]];
  }
  return self;
}

- (NSObject<FlutterBinaryMessenger>*)messenger {
  return _messengerProxy;
}

- (NSObject<FlutterTextureRegistry>*)textures {
  return [_target textures];
}

- (void)registerViewFactory:(NSObject<FlutterPlatformViewFactory>*)factory
                     withId:(NSString*)factoryId {
  [_target registerViewFactory:factory withId:factoryId];
}

- (void)registerViewFactory:(NSObject<FlutterPlatformViewFactory>*)factory
                              withId:(NSString*)factoryId
    gestureRecognizersBlockingPolicy:
        (FlutterPlatformViewGestureRecognizersBlockingPolicy)gestureRecognizersBlockingPolicy {
  [_target registerViewFactory:factory
                                withId:factoryId
      gestureRecognizersBlockingPolicy:gestureRecognizersBlockingPolicy];
}

- (UIViewController*)viewController {
  return [_target viewController];
}

- (void)publish:(NSObject*)value {
  [_target publish:value];
}

- (void)addMethodCallDelegate:(NSObject<FlutterPlugin>*)delegate
                      channel:(FlutterMethodChannel*)channel {
  [_target addMethodCallDelegate:delegate channel:channel];
}

- (void)addApplicationDelegate:(NSObject<FlutterPlugin>*)delegate {
  if (_disableLifecycleDelegates) {
    return;
  }
  [_target addApplicationDelegate:delegate];
}

- (void)addSceneDelegate:(NSObject<FlutterSceneLifeCycleDelegate>*)delegate
    API_AVAILABLE(ios(13.0)) {
  if (_disableLifecycleDelegates) {
    return;
  }
  [_target addSceneDelegate:delegate];
}

- (NSString*)lookupKeyForAsset:(NSString*)asset {
  return [_target lookupKeyForAsset:asset];
}

- (NSString*)lookupKeyForAsset:(NSString*)asset fromPackage:(NSString*)package {
  return [_target lookupKeyForAsset:asset fromPackage:package];
}

- (nullable NSObject*)valuePublishedByPlugin:(NSString*)pluginKey {
  return [_target valuePublishedByPlugin:pluginKey];
}

@end

@implementation SafePluginRegistry

- (instancetype)initWithTarget:(NSObject<FlutterPluginRegistry>*)target
      disabledLifecyclePlugins:(NSSet<NSString*>*)disabledLifecyclePlugins {
  self = [super init];
  if (self != nil) {
    _target = target;
    _disabledLifecyclePlugins = [disabledLifecyclePlugins copy];
  }
  return self;
}

- (nullable NSObject<FlutterPluginRegistrar>*)registrarForPlugin:(NSString*)pluginKey {
  NSObject<FlutterPluginRegistrar>* targetRegistrar = [_target registrarForPlugin:pluginKey];
  if (targetRegistrar == nil) {
    return nil;
  }
  BOOL disableLifecycle = [_disabledLifecyclePlugins containsObject:pluginKey];
  return [[SafePluginRegistrar alloc] initWithTarget:targetRegistrar
                           disableLifecycleDelegates:disableLifecycle];
}

- (BOOL)hasPlugin:(NSString*)pluginKey {
  return [_target hasPlugin:pluginKey];
}

- (nullable NSObject*)valuePublishedByPlugin:(NSString*)pluginKey {
  return [_target valuePublishedByPlugin:pluginKey];
}

@end
