#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
# 本机预览版工具链的自动测试入口不兼容旧 SDK，直接运行同一组 XCTest。
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
FRAMEWORK_DIR=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks
LIBRARY_DIR=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib
SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk
if [[ ! -d "$SDK_PATH" ]]; then SDK_PATH="$(xcrun --show-sdk-path)"; fi
sed '/@testable import TimerCore/d' Tests/TimerCoreTests/TimerCoreTests.swift > "$TEST_DIR/main.swift"
cat >> "$TEST_DIR/main.swift" <<'SWIFT'
let suite = TimerCoreTests.defaultTestSuite
suite.run()
guard let result = suite.testRun else { fatalError("测试未运行") }
print("执行 \(result.executionCount) 项测试，失败 \(result.totalFailureCount) 项")
exit(result.hasSucceeded && result.executionCount == 4 ? 0 : 1)
SWIFT
swiftc -sdk "$SDK_PATH" -I "$LIBRARY_DIR" -L "$LIBRARY_DIR" -Xlinker -rpath -Xlinker "$LIBRARY_DIR" -F "$FRAMEWORK_DIR" -framework XCTest -Xlinker -rpath -Xlinker "$FRAMEWORK_DIR" Sources/TimerCore/Reminder.swift "$TEST_DIR/main.swift" -o "$TEST_DIR/TimerCoreTests"
"$TEST_DIR/TimerCoreTests"
