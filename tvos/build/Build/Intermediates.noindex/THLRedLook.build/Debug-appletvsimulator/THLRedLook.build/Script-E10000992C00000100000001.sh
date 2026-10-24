#!/bin/sh
# Type a script or drag a script file from your workspace to insert its path.
#!/bin/bash
export TZ="Asia/Shanghai"
buildNumber=${BUILD_NUMBER:-$(TZ="Asia/Shanghai" date +%Y%m%d%H%M%S)}
if [ "$CONFIGURATION" == "Release" ] || [ -n "$BUILD_NUMBER" ] || [ "$FORCE_BUMP_BUILD" == "1" ]; then
    echo "Bumping build number to $buildNumber (Beijing Time)..."
    target_plist="${SRCROOT}/${INFOPLIST_FILE}"
    if [ -f "$target_plist" ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "$target_plist"
    fi
    if [ -n "$TARGET_BUILD_DIR" ] && [ -n "$INFOPLIST_PATH" ] && [ -f "$TARGET_BUILD_DIR/$INFOPLIST_PATH" ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "$TARGET_BUILD_DIR/$INFOPLIST_PATH" || true
    fi
else
    echo "$CONFIGURATION build - Keep current build number."
fi

HONGGUO_SRC="${SRCROOT}/../assets/sources/hongguo.js"
if [ -f "$HONGGUO_SRC" ] && [ -n "$TARGET_BUILD_DIR" ] && [ -n "$UNLOCALIZED_RESOURCES_FOLDER_PATH" ]; then
    mkdir -p "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
    cp -f "$HONGGUO_SRC" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/hongguo.js"
    echo "Synced hongguo.js to bundle resources."
fi

