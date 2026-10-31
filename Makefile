.PHONY: build run install test icon dmg clean

build:
	./scripts/build-app.sh

run: build
	open build/Seawall.app

# The watchdog relaunches the app by path, so keep it somewhere stable.
install: build
	rm -rf /Applications/Seawall.app /Applications/FocusLock.app
	cp -R build/Seawall.app /Applications/
	open /Applications/Seawall.app

# Command Line Tools ship Swift Testing but SwiftPM doesn't find it on its own; Xcode doesn't need this.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_DEV)/Frameworks -Xlinker -F -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib
endif

test:
	swift test $(TEST_FLAGS)

# Redraws Resources/AppIcon.icns after an edit to Resources/AppIcon.svg.
icon:
	swift scripts/render-icon.swift

# Signed, notarized dist/Seawall-<version>.dmg. Needs SIGN_IDENTITY; see docs/RELEASING.md.
dmg:
	./scripts/make-dmg.sh

clean:
	rm -rf .build build
