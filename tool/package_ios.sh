#!/usr/bin/env bash
# Packages the already-built device app. Run on macOS after flutter build ios.
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

app_path="build/ios/iphoneos/Runner.app"
output_dir="$project_dir/build/ios/ipa"
output_path="$output_dir/GreenFarm-Flutter-unsigned.ipa"

if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'This packaging script requires macOS (ditto and plutil).' >&2
  exit 1
fi

if [[ ! -d "$app_path" || ! -f "$app_path/Info.plist" ]]; then
  printf '%s\n' 'Device build missing. Run: flutter build ios --release --no-codesign' >&2
  exit 1
fi

executable_name="/usr/libexec/PlistBuddy"
executable_name="$("$executable_name" -c 'Print :CFBundleExecutable' "$app_path/Info.plist")"
if [[ ! -f "$app_path/$executable_name" ]]; then
  printf '%s\n' 'The app bundle does not contain its executable.' >&2
  exit 1
fi

# Reject a simulator bundle: it cannot be installed on a physical iPhone.
platform_name="$(/usr/libexec/PlistBuddy -c 'Print :DTPlatformName' "$app_path/Info.plist")"
if [[ "$platform_name" != iphoneos ]]; then
  printf '%s\n' "Expected iphoneos build, found: $platform_name" >&2
  exit 1
fi

staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/greenfarm-ipa.XXXXXX")"
trap 'rm -rf -- "$staging_dir"' EXIT
mkdir -p "$staging_dir/Payload" "$output_dir"

# ditto preserves the app bundle's executable bits and framework symlinks.
/usr/bin/ditto --norsrc "$app_path" "$staging_dir/Payload/Runner.app"
/usr/bin/ditto -c -k --norsrc --keepParent "$staging_dir/Payload" "$staging_dir/app.ipa"
/usr/bin/unzip -tq "$staging_dir/app.ipa"
mv -f "$staging_dir/app.ipa" "$output_path"

(
  cd "$output_dir"
  shasum -a 256 'GreenFarm-Flutter-unsigned.ipa' > 'GreenFarm-Flutter-unsigned.ipa.sha256'
)
printf 'Unsigned IPA: %s\n' "$output_path"
