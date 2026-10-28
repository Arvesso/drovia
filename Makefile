PROJECT      := Drovia.xcodeproj
SCHEME       := Drovia
DERIVED_DATA := build
APP          := $(DERIVED_DATA)/Build/Products/Debug/Drovia.app
RELEASE_APP  := $(DERIVED_DATA)/Build/Products/Release/Drovia.app
XCODEBUILD   := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED_DATA)

.PHONY: gen build release run test format lint icon clean logs signing docs-images

# Warns when a local tool isn't the version CI uses (from .swiftformat_version / .xcodegen_version):
# versions can format or generate differently.
check_version = @have=$$($(1) --version | grep -oE '[0-9]+(\.[0-9]+)+' | head -1); want=$$(tr -d '[:space:]' < $(2)); \
	[ "$$have" = "$$want" ] || echo "warning: $(1) is $$have, the project uses $$want ($(2)); results may differ from CI" >&2

gen:
	$(call check_version,xcodegen,.xcodegen_version)
	xcodegen generate --quiet

build: gen
	$(XCODEBUILD) -configuration Debug build -quiet

release: gen
	$(XCODEBUILD) -configuration Release build -quiet
	@echo "Built $(RELEASE_APP)"

run: build
	-pkill -x Drovia; while pgrep -qx Drovia; do sleep 0.1; done
	open $(APP)

test: gen
	$(XCODEBUILD) test -quiet

format:
	$(call check_version,swiftformat,.swiftformat_version)
	swiftformat .

lint:
	$(call check_version,swiftformat,.swiftformat_version)
	swiftformat --lint .

icon:
	swift Scripts/render-icon.swift Drovia/Resources/Assets.xcassets/AppIcon.appiconset

clean:
	rm -rf $(DERIVED_DATA) $(PROJECT)

logs:
	log stream --level debug --predicate 'subsystem == "com.arvesso.drovia"'

# Signs builds with your Apple Development certificate (add your Apple ID in Xcode → Settings → Accounts first).
signing:
	@identity=$$(security find-identity -v -p codesigning | grep -m1 '"Apple Development' | sed -E 's/.*"(.*)"/\1/'); \
	if [ -z "$$identity" ]; then \
		if security find-identity -p codesigning | grep -q '"Apple Development'; then \
			echo "Your Apple Development certificate is not trusted: the Apple WWDR G3 intermediate certificate is missing."; \
			echo "Install it: open https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer and add it to the login keychain."; \
		else \
			echo "No Apple Development certificate found. Add your Apple ID in Xcode → Settings → Accounts, then Manage Certificates → + → Apple Development."; \
		fi; exit 1; \
	fi; \
	team=$$(security find-certificate -c "$$identity" -p | openssl x509 -noout -subject -nameopt multiline | awk -F' = ' '/organizationalUnitName/ {print $$2}'); \
	printf 'CODE_SIGN_IDENTITY = Apple Development\nDEVELOPMENT_TEAM = %s\n' "$$team" > Config/Local.xcconfig; \
	echo "Signing with $$identity (team $$team). Written to Config/Local.xcconfig"

# Re-renders the README images in docs/images (in English).
docs-images: gen
	TEST_RUNNER_DROVIA_DOCS=1 $(XCODEBUILD) test -quiet -only-testing:DroviaTests/DocsImages -testLanguage en -testRegion US
