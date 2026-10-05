SIMULATOR ?= iPhone 17

PROJECT := Commonplace.xcodeproj
SCHEME := Commonplace
DESTINATION := platform=iOS Simulator,name=$(SIMULATOR)

.PHONY: build test lint

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' build

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' test -only-testing:CommonplaceTests

lint:
	xcrun swift-format lint --recursive --strict Commonplace CommonplaceTests
