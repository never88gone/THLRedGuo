#import <Flutter/Flutter.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface THLAppLifecycleGuard : NSObject

+ (BOOL)isEngineStopping;
+ (void)markEngineStopping;
+ (void)markEngineActive;

@end

@interface SafeBinaryMessengerProxy : NSObject <FlutterBinaryMessenger>

@property(nonatomic, strong, readonly) NSObject<FlutterBinaryMessenger>* target;

- (instancetype)initWithTarget:(NSObject<FlutterBinaryMessenger>*)target NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface SafePluginRegistrar : NSObject <FlutterPluginRegistrar>

@property(nonatomic, strong, readonly) NSObject<FlutterPluginRegistrar>* target;
@property(nonatomic, assign, readonly) BOOL disableLifecycleDelegates;

- (instancetype)initWithTarget:(NSObject<FlutterPluginRegistrar>*)target
     disableLifecycleDelegates:(BOOL)disableLifecycleDelegates NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface SafePluginRegistry : NSObject <FlutterPluginRegistry>

@property(nonatomic, strong, readonly) NSObject<FlutterPluginRegistry>* target;
@property(nonatomic, copy, readonly) NSSet<NSString*>* disabledLifecyclePlugins;

- (instancetype)initWithTarget:(NSObject<FlutterPluginRegistry>*)target
      disabledLifecyclePlugins:(NSSet<NSString*>*)disabledLifecyclePlugins
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
