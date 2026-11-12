#!/usr/bin/env bash
set -euo pipefail

# Match android/app/build.gradle.kts (ndkVersion = flutter.ndkVersion).
extension="${FLUTTER_ROOT:?}/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt"
ndk_version=$(sed -nE 's/^[[:space:]]*val ndkVersion: String = "([0-9.]+)".*/\1/p' "$extension")
if [[ ! "$ndk_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::Cannot determine the NDK version from $extension"
  exit 1
fi

sdk_root=$(cd "${ANDROID_HOME:-${ANDROID_SDK_ROOT:?}}" && pwd -P)
sdkmanager="$sdk_root/cmdline-tools/latest/bin/sdkmanager"
if [[ "$sdk_root" == / || ! -x "$sdkmanager" ]]; then
  echo "::error::Expected an Android SDK with sdkmanager at $sdk_root"
  exit 1
fi
ndk_dir="$sdk_root/ndk/$ndk_version"

ndk_ready() {
  [[ -f "$ndk_dir/package.xml" &&
     -f "$ndk_dir/source.properties" &&
     -f "$ndk_dir/build/cmake/android.toolchain.cmake" &&
     -x "$ndk_dir/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]] &&
    [[ "$(sed -nE 's/^Pkg.Revision[[:space:]]*=[[:space:]]*(.*)/\1/p' "$ndk_dir/source.properties" | tr -d '\r')" == "$ndk_version" ]]
}

if ndk_ready; then
  echo "NDK $ndk_version is already installed."
  exit 0
fi

df -h "$sdk_root"
for attempt in 1 2 3; do
  # This runs before Gradle on an isolated CI runner. Discard an incomplete
  # target package and SDK Manager staging directories, including broken ZIPs.
  rm -rf -- "$ndk_dir"
  if [[ -d "$sdk_root/.temp" ]]; then
    find "$sdk_root/.temp" -mindepth 1 -maxdepth 1 -type d \
      -name 'PackageOperation*' -exec rm -rf -- {} +
  fi
  echo "Installing NDK $ndk_version (attempt $attempt/3)..."
  if "$sdkmanager" --sdk_root="$sdk_root" --install "ndk;$ndk_version" </dev/null && ndk_ready; then
    echo "NDK $ndk_version installed and verified."
    exit 0
  fi
  echo "::warning::NDK installation attempt $attempt failed or was incomplete."
  if [[ "$attempt" -lt 3 ]]; then
    sleep "$((attempt * 5))"
  fi
done

echo "::error::NDK $ndk_version could not be installed after 3 attempts."
exit 1
