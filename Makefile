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

.PHONY: app dmg build run test check-env

app:
	sh Scripts/build-app.sh

dmg:
	sh Scripts/build-dmg.sh

build:
	CLANG_MODULE_CACHE_PATH="$(CLANG_MODULE_CACHE_PATH)" swift build $(SWIFT_BUILD_SANDBOX_FLAGS)

run:
	swift run PastePilot

check-env:
	@test -d "$(TESTING_FRAMEWORK_DIR)" || ( \
		echo "Swift Testing framework not found at $(TESTING_FRAMEWORK_DIR)."; \
		echo "Install Xcode 16+ or Swift command-line tools, then run make test again."; \
		exit 1; \
	)

test: check-env
	CLANG_MODULE_CACHE_PATH="$(CLANG_MODULE_CACHE_PATH)" swift test $(TEST_SCRATCH_FLAG) $(SWIFT_TEST_SANDBOX_FLAGS) $(TEST_FLAGS)
