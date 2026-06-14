DEVELOPER_DIR := $(shell xcode-select -p)
TESTING_FRAMEWORK_DIR := $(DEVELOPER_DIR)/Library/Developer/Frameworks
TESTING_LIBRARY_DIR := $(DEVELOPER_DIR)/Library/Developer/usr/lib
CLANG_MODULE_CACHE_PATH ?= $(CURDIR)/.build/clang-module-cache
TEST_SCRATCH_PATH ?=
TEST_SCRATCH_FLAG := $(if $(TEST_SCRATCH_PATH),--scratch-path "$(TEST_SCRATCH_PATH)")
SWIFT_BUILD_SANDBOX_FLAGS ?= --disable-sandbox
SWIFT_TEST_SANDBOX_FLAGS ?= --disable-sandbox
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
	CLANG_MODULE_CACHE_PATH="$(CLANG_MODULE_CACHE_PATH)" swift build $(SWIFT_BUILD_SANDBOX_FLAGS)

run:
	swift run PastePilot

test:
	CLANG_MODULE_CACHE_PATH="$(CLANG_MODULE_CACHE_PATH)" swift test $(TEST_SCRATCH_FLAG) $(SWIFT_TEST_SANDBOX_FLAGS) $(TEST_FLAGS)
