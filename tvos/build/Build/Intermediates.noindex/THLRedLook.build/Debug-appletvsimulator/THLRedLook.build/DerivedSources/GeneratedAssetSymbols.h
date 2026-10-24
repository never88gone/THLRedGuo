#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.never88gone.redlook";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "App Icon - Small/Front/Content" asset catalog image resource.
static NSString * const ACImageNameAppIconSmallFrontContent AC_SWIFT_PRIVATE = @"App Icon - Small/Front/Content";

/// The "App Icon - Small/Back/Content" asset catalog image resource.
static NSString * const ACImageNameAppIconSmallBackContent AC_SWIFT_PRIVATE = @"App Icon - Small/Back/Content";

/// The "App Icon - Large/Back/Content" asset catalog image resource.
static NSString * const ACImageNameAppIconLargeBackContent AC_SWIFT_PRIVATE = @"App Icon - Large/Back/Content";

/// The "App Icon - Large/Front/Content" asset catalog image resource.
static NSString * const ACImageNameAppIconLargeFrontContent AC_SWIFT_PRIVATE = @"App Icon - Large/Front/Content";

/// The "LaunchBackground" asset catalog image resource.
static NSString * const ACImageNameLaunchBackground AC_SWIFT_PRIVATE = @"LaunchBackground";

/// The "LaunchImage" asset catalog image resource.
static NSString * const ACImageNameLaunchImage AC_SWIFT_PRIVATE = @"LaunchImage";

/// The "LaunchLogo" asset catalog image resource.
static NSString * const ACImageNameLaunchLogo AC_SWIFT_PRIVATE = @"LaunchLogo";

/// The "Top Shelf Image" asset catalog image resource.
static NSString * const ACImageNameTopShelfImage AC_SWIFT_PRIVATE = @"Top Shelf Image";

/// The "Top Shelf Image Wide" asset catalog image resource.
static NSString * const ACImageNameTopShelfImageWide AC_SWIFT_PRIVATE = @"Top Shelf Image Wide";

/// The "applogo" asset catalog image resource.
static NSString * const ACImageNameApplogo AC_SWIFT_PRIVATE = @"applogo";

/// The "github_qr" asset catalog image resource.
static NSString * const ACImageNameGithubQr AC_SWIFT_PRIVATE = @"github_qr";

/// The "telegram_icon" asset catalog image resource.
static NSString * const ACImageNameTelegramIcon AC_SWIFT_PRIVATE = @"telegram_icon";

/// The "telegram_qr" asset catalog image resource.
static NSString * const ACImageNameTelegramQr AC_SWIFT_PRIVATE = @"telegram_qr";

#undef AC_SWIFT_PRIVATE
