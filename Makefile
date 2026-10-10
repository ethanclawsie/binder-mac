APP_NAME = mousebutton.app
DIST_APP = dist/$(APP_NAME)
INSTALL_DIR = /Applications
BUNDLE_ID = com.ethanclawsie.mousebutton

.PHONY: all build app run clean install uninstall

all: app

build:
	@swift build -c release

app:
	@./scripts/build-app.sh

run: app
	@echo "==> Launching $(DIST_APP)..."
	@open $(DIST_APP)

clean:
	@swift package clean
	@rm -rf dist .build
	@echo "==> Cleaned."

install: app
	@echo "==> Installing to $(INSTALL_DIR)..."
	@pkill -f "/Applications/mousebutton.app" 2>/dev/null || true
	@sleep 0.5
	@rm -rf $(INSTALL_DIR)/$(APP_NAME)
	@cp -R $(DIST_APP) $(INSTALL_DIR)/
	@xattr -cr $(INSTALL_DIR)/$(APP_NAME)
	@codesign --force --sign - --requirements '=designated => identifier "$(BUNDLE_ID)"' --timestamp=none $(INSTALL_DIR)/$(APP_NAME)
	@echo "==> Launching $(INSTALL_DIR)/$(APP_NAME)..."
	@open $(INSTALL_DIR)/$(APP_NAME)
	@echo "==> Successfully installed and launched."

uninstall:
	@pkill -f "/Applications/mousebutton.app" 2>/dev/null || true
	@rm -rf $(INSTALL_DIR)/$(APP_NAME)
	@echo "==> Successfully uninstalled."
