BIN_NAME = mousebutton
APP_NAME = mousebutton.app
INSTALL_DIR = /Applications
BUNDLE_ID = com.ethanclawsie.mousebutton

.PHONY: all build app run clean install uninstall

all: build app

build:
	@echo "==> Compiling $(BIN_NAME) with optimizations..."
	@swiftc -O -whole-module-optimization main.swift -o $(BIN_NAME)
	@strip -x $(BIN_NAME)
	@echo "==> Built $(BIN_NAME) successfully ($$(ls -lh $(BIN_NAME) | awk '{print $$5}'))"

app: build
	@echo "==> Packaging into $(APP_NAME)..."
	@mkdir -p $(APP_NAME)/Contents/MacOS
	@mkdir -p $(APP_NAME)/Contents/Resources
	@cp $(BIN_NAME) $(APP_NAME)/Contents/MacOS/$(BIN_NAME)
	@echo '<?xml version="1.0" encoding="UTF-8"?>\
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\
	<plist version="1.0">\
	<dict>\
		<key>CFBundleDevelopmentRegion</key>\
		<string>en</string>\
		<key>CFBundleDisplayName</key>\
		<string>mousebutton</string>\
		<key>CFBundleExecutable</key>\
		<string>$(BIN_NAME)</string>\
		<key>CFBundleIdentifier</key>\
		<string>$(BUNDLE_ID)</string>\
		<key>CFBundleInfoDictionaryVersion</key>\
		<string>6.0</string>\
		<key>CFBundleName</key>\
		<string>mousebutton</string>\
		<key>CFBundlePackageType</key>\
		<string>APPL</string>\
		<key>CFBundleShortVersionString</key>\
		<string>1.0</string>\
		<key>CFBundleVersion</key>\
		<string>1</string>\
		<key>LSMinimumSystemVersion</key>\
		<string>14.0</string>\
		<key>LSUIElement</key>\
		<true/>\
		<key>NSHighResolutionCapable</key>\
		<true/>\
	</dict>\
	</plist>' > $(APP_NAME)/Contents/Info.plist
	@printf 'APPL????' > $(APP_NAME)/Contents/PkgInfo
	@codesign --force --sign - --requirements '=designated => identifier "$(BUNDLE_ID)"' --timestamp=none $(APP_NAME)
	@codesign --verify --strict $(APP_NAME)
	@echo "==> Created and verified signature for $(APP_NAME)"

run: app
	@echo "==> Launching $(APP_NAME)..."
	@open $(APP_NAME)

clean:
	@rm -rf $(BIN_NAME) $(APP_NAME)
	@echo "==> Cleaned."

install: app
	@echo "==> Installing $(APP_NAME) to $(INSTALL_DIR)..."
	@rm -rf $(INSTALL_DIR)/$(APP_NAME)
	@cp -R $(APP_NAME) $(INSTALL_DIR)/
	@xattr -cr $(INSTALL_DIR)/$(APP_NAME)
	@codesign --force --sign - --requirements '=designated => identifier "$(BUNDLE_ID)"' --timestamp=none $(INSTALL_DIR)/$(APP_NAME)
	@echo "==> Launching $(INSTALL_DIR)/$(APP_NAME)..."
	@open $(INSTALL_DIR)/$(APP_NAME)
	@echo "==> Successfully installed and launched from $(INSTALL_DIR)/$(APP_NAME)"

uninstall:
	@killall $(BIN_NAME) 2>/dev/null || true
	@rm -rf $(INSTALL_DIR)/$(APP_NAME)
	@echo "==> Successfully uninstalled."
