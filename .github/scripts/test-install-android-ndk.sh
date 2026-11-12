#!/usr/bin/env bash
set -euo pipefail

installer="$(cd "$(dirname "$0")" && pwd)/install-android-ndk.sh"
temp_root=$(cd "${TMPDIR:-/tmp}" && pwd -P)
fixture=$(mktemp -d "$temp_root/ndk-recovery.XXXXXX")
[[ "$fixture" == "$temp_root"/ndk-recovery.* ]]
trap 'rm -rf -- "$fixture"' EXIT
export FLUTTER_ROOT="$fixture/flutter"
export ANDROID_HOME="$fixture/sdk root"
export TEST_STATE="$fixture/state"
export TEST_FAILURES=2
extension="$FLUTTER_ROOT/packages/flutter_tools/gradle/src/main/kotlin"
mkdir -p "$extension" "$ANDROID_HOME/cmdline-tools/latest/bin" "$fixture/bin"
echo '    val ndkVersion: String = "28.2.13676358"' > "$extension/FlutterExtension.kt"
# Avoid real delays and downloads; exercise the actual installer control flow.
printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture/bin/sleep"
chmod +x "$fixture/bin/sleep"
export PATH="$fixture/bin:$PATH"
cat > "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "--sdk_root=$ANDROID_HOME" && "$2" == --install && "$3" == 'ndk;28.2.13676358' ]]
attempt=$(cat "$TEST_STATE" 2>/dev/null || echo 0)
attempt=$((attempt + 1))
echo "$attempt" > "$TEST_STATE"
ndk="$ANDROID_HOME/ndk/28.2.13676358"
# A retry must start with a fresh download and no incomplete installation.
[[ ! -e "$ANDROID_HOME/.temp/PackageOperation01" && ! -e "$ndk" ]]
mkdir -p "$ndk" "$ANDROID_HOME/.temp/PackageOperation01"
echo 'Pkg.Revision = 28.2.13676358' > "$ndk/source.properties"
if (( attempt <= TEST_FAILURES )); then
  echo 'Error reading Zip content from a SeekableByteChannel.' >&2
  exit "${TEST_FAILURE_EXIT:-1}"
fi
mkdir -p "$ndk/build/cmake" "$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
touch "$ndk/package.xml" "$ndk/build/cmake/android.toolchain.cmake"
printf '#!/usr/bin/env bash\nexit 0\n' > "$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
chmod +x "$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
STUB
chmod +x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
mkdir -p "$ANDROID_HOME/ndk/other-version"
touch "$ANDROID_HOME/ndk/other-version/keep"

# Two corrupt downloads recover on the third attempt; other NDKs survive.
bash "$installer" > "$fixture/recovery.log" 2>&1 || {
  cat "$fixture/recovery.log"
  exit 1
}
[[ "$(cat "$TEST_STATE")" == 3 && -f "$ANDROID_HOME/ndk/other-version/keep" ]]
# A complete installation is reused without calling SDK Manager.
bash "$installer"
[[ "$(cat "$TEST_STATE")" == 3 ]]

for failure_exit in 1 0; do
  rm -rf -- "$ANDROID_HOME/ndk/28.2.13676358"
  rm -f -- "$TEST_STATE"
  export TEST_FAILURES=3 TEST_FAILURE_EXIT="$failure_exit"
  if bash "$installer" > "$fixture/failure.log" 2>&1; then
    echo 'Expected installation failure, even if SDK Manager reports success.' >&2
    exit 1
  fi
  [[ "$(cat "$TEST_STATE")" == 3 ]]
  grep -q 'could not be installed after 3 attempts' "$fixture/failure.log"
done
echo 'NDK recovery tests passed.'
