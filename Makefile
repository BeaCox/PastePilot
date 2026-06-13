DEVELOPER_DIR := $(shell xcode-select -p)
TESTING_FRAMEWORK_DIR := $(DEVELOPER_DIR)/Library/Developer/Frameworks
TESTING_LIBRARY_DIR := $(DEVELOPER_DIR)/Library/Developer/usr/lib
TEST_SCRATCH_PATH := /tmp/PastePilotTests-$(shell id -u)
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
	swift test --scratch-path "$(TEST_SCRATCH_PATH)" $(TEST_FLAGS)
