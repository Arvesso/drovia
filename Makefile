PROJECT      := Drovia.xcodeproj
SCHEME       := Drovia
DERIVED_DATA := build
APP          := $(DERIVED_DATA)/Build/Products/Debug/Drovia.app
XCODEBUILD   := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED_DATA)

.PHONY: gen build run test format lint icon clean

gen:
	xcodegen generate --quiet

build: gen
	$(XCODEBUILD) -configuration Debug build -quiet

run: build
	-pkill -x Drovia
	open $(APP)

test: gen
	$(XCODEBUILD) test -quiet

format:
	swiftformat .

lint:
	swiftformat --lint .

icon:
	swift Scripts/render-icon.swift Drovia/Resources/Assets.xcassets/AppIcon.appiconset

clean:
	rm -rf $(DERIVED_DATA) $(PROJECT)
