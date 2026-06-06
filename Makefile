.PHONY: app build run test

app:
	sh Scripts/build-app.sh

build:
	swift build

run:
	swift run PastePilot

test:
	@mkdir -p .build/checks
	swiftc \
		Sources/PastePilot/Localization.swift \
		Sources/PastePilot/ClipboardItem.swift \
		Sources/PastePilot/ContentAnalyzer.swift \
		Sources/PastePilot/ContentTransformer.swift \
		Sources/PastePilot/AppSettings.swift \
		Sources/PastePilot/HotKeyRecorder.swift \
		Sources/PastePilot/ClipboardStore.swift \
		Sources/PastePilot/ClipboardAction.swift \
		Tests/CoreChecks/main.swift \
		-o .build/checks/PastePilotCoreChecks
	.build/checks/PastePilotCoreChecks
