DEVELOPER_DIR := $(shell xcode-select -p 2>/dev/null)
TESTING_FRAMEWORK_DIR := $(shell \
	for dir in \
		"$(DEVELOPER_DIR)/Library/Developer/Frameworks" \
		"/Library/Developer/CommandLineTools/Library/Developer/Frameworks"; do \
		if [ -d "$$dir/Testing.framework" ]; then \
			echo "$$dir"; \
			exit 0; \
		fi; \
	done \
)
TESTING_LIBRARY_DIR := $(patsubst %/Frameworks,%/usr/lib,$(TESTING_FRAMEWORK_DIR))
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
	@test -d "$(TESTING_FRAMEWORK_DIR)/Testing.framework" || ( \
		echo "Swift Testing framework not found."; \
		echo "xcode-select: $(DEVELOPER_DIR)"; \
		echo "Checked:"; \
		echo "  $(DEVELOPER_DIR)/Library/Developer/Frameworks/Testing.framework"; \
		echo "  /Library/Developer/CommandLineTools/Library/Developer/Frameworks/Testing.framework"; \
		echo "Install Xcode 16+ or Swift command-line tools, then run make test again."; \
		exit 1; \
	)

test: check-env
	CLANG_MODULE_CACHE_PATH="$(CLANG_MODULE_CACHE_PATH)" swift test $(TEST_SCRATCH_FLAG) $(SWIFT_TEST_SANDBOX_FLAGS) $(TEST_FLAGS)
