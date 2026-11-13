#!/usr/bin/env bash
# Builds the game as a static library for iPhone/iPad (arm64): target/aarch64-apple-ios/release/libhorizon_ios.a
# Needs macOS with Xcode (the iOS SDK) and `rustup target add aarch64-apple-ios`.
set -euo pipefail
cd "$(dirname "$0")/.."
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-17.0}"
rustup target add aarch64-apple-ios
cargo build --release -p horizon-ios --target aarch64-apple-ios
ls -lh target/aarch64-apple-ios/release/libhorizon_ios.a
