#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
# We need to navigate to the root of the repo (assuming ios/ci_scripts location).
cd $CI_PRIMARY_REPOSITORY_PATH

echo "📦 Installing Flutter..."
# Clone Flutter SDK (stable channel) if not already present
if [ ! -x "$HOME/flutter/bin/flutter" ]; then
    git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter
fi
export PATH="$PATH:$HOME/flutter/bin"

echo "🩺 Verifying Flutter..."
flutter precache --ios

echo "📦 Installing Dependencies..."
# Install Flutter pub packages
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
# Install CocoaPods (Xcode Cloud images usually have Homebrew installed)
if ! command -v pod &> /dev/null; then
    echo "Installing CocoaPods..."
    brew install cocoapods
fi

echo "🪄 Installing Pods..."
# Clean pods to ensure compatibility with platform changes
rm -rf ios/Pods ios/Podfile.lock
# Navigate to ios folder to run pod install
cd ios
pod repo update
pod install

echo "✅ Post-clone setup complete."
exit 0
