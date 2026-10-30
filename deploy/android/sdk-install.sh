#!/bin/bash
# Install the remaining Android SDK components (idempotent).
# Cached under my-project/.android-cache so it survives platform resets.
C=/home/z/my-project/.android-cache
export JAVA_HOME="$C/jdk/usr/lib/jvm/java-21-openjdk-amd64"
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_SDK_ROOT="$C/sdk"
export ANDROID_USER_HOME="$C/android-user"

echo "== sdkmanager install start $(date)"
yes | "$C/sdk/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$C/sdk" \
    "platform-tools" \
    "system-images;android-30;google_apis;x86_64"
RC=$?
echo "== sdkmanager exit code: $RC"
exit $RC
