import Foundation
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

    /// The "AccentColor" asset catalog color resource.
    static let accent = DeveloperToolsSupport.ColorResource(name: "AccentColor", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "App Icon - Large" asset catalog resource namespace.
    enum AppIconLarge {

        /// The "App Icon - Large/Back" asset catalog resource namespace.
        enum Back {

        }

        /// The "App Icon - Large/Front" asset catalog resource namespace.
        enum Front {

        }

    }

    /// The "App Icon - Small" asset catalog resource namespace.
    enum AppIconSmall {

        /// The "App Icon - Small/Back" asset catalog resource namespace.
        enum Back {

            /// The "App Icon - Small/Back/Content" asset catalog image resource.
            static let content = DeveloperToolsSupport.ImageResource(name: "App Icon - Small/Back/Content", bundle: resourceBundle)

        }

        /// The "App Icon - Small/Front" asset catalog resource namespace.
        enum Front {

            /// The "App Icon - Small/Front/Content" asset catalog image resource.
            static let content = DeveloperToolsSupport.ImageResource(name: "App Icon - Small/Front/Content", bundle: resourceBundle)

        }

    }

    /// The "LaunchBackground" asset catalog image resource.
    static let launchBackground = DeveloperToolsSupport.ImageResource(name: "LaunchBackground", bundle: resourceBundle)

    /// The "LaunchImage" asset catalog image resource.
    static let launch = DeveloperToolsSupport.ImageResource(name: "LaunchImage", bundle: resourceBundle)

    /// The "LaunchLogo" asset catalog image resource.
    static let launchLogo = DeveloperToolsSupport.ImageResource(name: "LaunchLogo", bundle: resourceBundle)

    /// The "Top Shelf Image" asset catalog image resource.
    static let topShelf = DeveloperToolsSupport.ImageResource(name: "Top Shelf Image", bundle: resourceBundle)

    /// The "Top Shelf Image Wide" asset catalog image resource.
    static let topShelfImageWide = DeveloperToolsSupport.ImageResource(name: "Top Shelf Image Wide", bundle: resourceBundle)

    /// The "applogo" asset catalog image resource.
    static let applogo = DeveloperToolsSupport.ImageResource(name: "applogo", bundle: resourceBundle)

    /// The "github_qr" asset catalog image resource.
    static let githubQr = DeveloperToolsSupport.ImageResource(name: "github_qr", bundle: resourceBundle)

    /// The "telegram_icon" asset catalog image resource.
    static let telegramIcon = DeveloperToolsSupport.ImageResource(name: "telegram_icon", bundle: resourceBundle)

    /// The "telegram_qr" asset catalog image resource.
    static let telegramQr = DeveloperToolsSupport.ImageResource(name: "telegram_qr", bundle: resourceBundle)

}

