fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## tvos

### tvos install_profiles

```sh
[bundle exec] fastlane tvos install_profiles
```

安装 fastlane 目录下的 tvOS 生产描述文件

### tvos setup_signing

```sh
[bundle exec] fastlane tvos setup_signing
```

配置 tvOS Xcode 工程代码签名设置

### tvos build_ipa

```sh
[bundle exec] fastlane tvos build_ipa
```

打包 Apple TV (tvOS) 独立应用 IPA (本地或导出)

### tvos beta

```sh
[bundle exec] fastlane tvos beta
```

发布 tvOS Beta 版本到 TestFlight (对齐 thldytv)

### tvos upload_appstore

```sh
[bundle exec] fastlane tvos upload_appstore
```

编译并上传 App Store 正式版本 (对齐 thldytv)

### tvos build_simulator

```sh
[bundle exec] fastlane tvos build_simulator
```

编译 tvOS 模拟器版本（适用于自动化验证与无证书环境）

### tvos release_app_store

```sh
[bundle exec] fastlane tvos release_app_store
```

发布 tvOS 到 TestFlight (兼容 release_app_store 命名)

### tvos upload_testflight

```sh
[bundle exec] fastlane tvos upload_testflight
```

发布 tvOS 到 TestFlight (别名)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
