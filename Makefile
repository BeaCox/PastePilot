DEVELOPER_DIR := $(shell xcode-select -p)
TESTING_FRAMEWORK_DIR := $(DEVELOPER_DIR)/Library/Developer/Frameworks
TESTING_LIBRARY_DIR := $(DEVELOPER_DIR)/Library/Developer/usr/lib
HOST_ARCH := $(shell uname -m)
TEST_BUNDLE := .build/$(HOST_ARCH)-apple-macosx/debug/PastePilotPackageTests.xctest
TEST_EXECUTABLE := $(TEST_BUNDLE)/Contents/MacOS/PastePilotPackageTests
TEST_FLAGS := --enable-swift-testing \
	-Xswiftc -F -Xswiftc "$(TESTING_FRAMEWORK_DIR)" \
	-Xlinker -F -Xlinker "$(TESTING_FRAMEWORK_DIR)" \
	-Xlinker -rpath -Xlinker "$(TESTING_FRAMEWORK_DIR)" \
	-Xlinker -rpath -Xlinker "$(TESTING_LIBRARY_DIR)"

.PHONY: app dmg build run test

app:
	sh Scripts/build-app.sh

dmg:
	sh Scripts/build-dmg.sh

build:
	swift build

run:
	swift run PastePilot

test:
	swift build --build-tests $(TEST_FLAGS)
	xattr -dr com.apple.provenance "$(TEST_BUNDLE)" 2>/dev/null || true
	codesign --force --sign - "$(TEST_EXECUTABLE)"
	swift test --skip-build $(TEST_FLAGS)
