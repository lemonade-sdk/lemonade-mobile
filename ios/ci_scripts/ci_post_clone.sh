#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
# We need to navigate to the root of the repo (assuming ios/ci_scripts location).
cd $CI_PRIMARY_REPOSITORY_PATH

echo "📦 Installing Flutter..."
# Clone Flutter SDK (stable channel) if not already present
# Use TMPDIR if HOME is not writable in CI
FLUTTER_DIR="${TMPDIR:-$HOME}/flutter"
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
    echo "Cloning Flutter to $FLUTTER_DIR..."
    git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$FLUTTER_DIR"
fi
export PATH="$PATH:$FLUTTER_DIR/bin"

echo "🩺 Verifying Flutter..."
flutter --version
flutter precache --ios

echo "📦 Installing Dependencies..."
# Install Flutter pub packages
flutter pub get

# Only run build_runner if the package is available
if grep -q "build_runner" pubspec.yaml; then
    echo "Running build_runner..."
    flutter pub run build_runner build --delete-conflicting-outputs
else
    echo "build_runner not found in dependencies, skipping..."
fi

# Install CocoaPods (Xcode Cloud images usually have Homebrew installed)
if ! command -v pod &> /dev/null; then
    echo "Installing CocoaPods..."
    # Try to install with brew, but don't fail if it doesn't work
    brew install cocoapods || echo "Warning: Could not install CocoaPods with brew"
fi

echo "🪄 Installing Pods..."
# Clean pods to ensure compatibility with platform changes
rm -rf ios/Pods ios/Podfile.lock
# Navigate to ios folder to run pod install
cd ios

# Set proper locale for CocoaPods
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Update pod repo (may fail in some CI environments, but try anyway)
pod repo update || echo "Warning: pod repo update failed, continuing..."

# Install pods
pod install

echo "✅ Post-clone setup complete."
exit 0
