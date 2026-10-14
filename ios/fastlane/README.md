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

### ios build_ipa

```sh
[bundle exec] fastlane ios build_ipa
```

Build Flutter iOS IPA bundle

### ios build_app_store_ipa

```sh
[bundle exec] fastlane ios build_app_store_ipa
```

Build and export Release App Store IPA using fastlane/thlredlook_iOS_dis.mobileprovision

### ios build_dev_ipa

```sh
[bundle exec] fastlane ios build_dev_ipa
```

Build and export Development IPA using fastlane/thlredlool_iOS_dev.mobileprovision

### ios release_app_store

```sh
[bundle exec] fastlane ios release_app_store
```

Release a new build to Apple Store / TestFlight

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
