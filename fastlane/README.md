fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios install_profiles

```sh
[bundle exec] fastlane ios install_profiles
```

安装 iOS 生产发布证书描述文件

### ios setup_signing

```sh
[bundle exec] fastlane ios setup_signing
```

配置 iOS Xcode 项目签名设置

### ios build_ipa

```sh
[bundle exec] fastlane ios build_ipa
```

打包 iOS IPA (App Store / TestFlight 签名)

### ios release_app_store

```sh
[bundle exec] fastlane ios release_app_store
```

发布 iOS 应用到 App Store / TestFlight

----


## Mac

### mac install_profiles

```sh
[bundle exec] fastlane mac install_profiles
```

安装 macOS 生产发布证书描述文件

### mac setup_signing

```sh
[bundle exec] fastlane mac setup_signing
```

配置 macOS Xcode 项目签名设置

### mac build_pkg

```sh
[bundle exec] fastlane mac build_pkg
```

打包 macOS 归档与 pkg

### mac release_app_store

```sh
[bundle exec] fastlane mac release_app_store
```

发布 macOS 应用到 App Store / TestFlight

----


## tvos

### tvos install_profiles

```sh
[bundle exec] fastlane tvos install_profiles
```

安装 Apple TV (tvOS) 生产发布证书描述文件

### tvos setup_signing

```sh
[bundle exec] fastlane tvos setup_signing
```

配置 tvOS Xcode 项目签名设置

### tvos build_ipa

```sh
[bundle exec] fastlane tvos build_ipa
```

打包 Apple TV (tvOS) IPA

### tvos release_app_store

```sh
[bundle exec] fastlane tvos release_app_store
```

发布 tvOS 应用到 App Store / TestFlight

### tvos beta

```sh
[bundle exec] fastlane tvos beta
```

发布 tvOS Beta 到 TestFlight (别名)

### tvos upload_testflight

```sh
[bundle exec] fastlane tvos upload_testflight
```

发布 tvOS 到 TestFlight

### tvos upload_appstore

```sh
[bundle exec] fastlane tvos upload_appstore
```

发布 tvOS 到 App Store (别名)

----


## Android

### android build_apk

```sh
[bundle exec] fastlane android build_apk
```

打包 Android APK

### android build_bundle

```sh
[bundle exec] fastlane android build_bundle
```

打包 Android App Bundle (AAB)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
