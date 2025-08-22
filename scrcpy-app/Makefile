# Makefile for Scrcpy Remote iOS App
# This Makefile provides targets to build and archive the Scrcpy Remote app

# Configuration
PROJECT_NAME = Scrcpy Remote
SCHEME_NAME = Scrcpy Remote
CONFIGURATION = Debug
BUILD_DIR = build
ARCHIVE_PATH = $(BUILD_DIR)/$(PROJECT_NAME).xcarchive
IPA_PATH = $(BUILD_DIR)/$(PROJECT_NAME).ipa
EXPORT_OPTIONS_PLIST = $(BUILD_DIR)/ExportOptions.plist

# Xcode build settings
XCODEBUILD = xcodebuild
PROJECT_FILE = "$(PROJECT_NAME).xcodeproj"

# Default target
.PHONY: all clean build-app archive export-ipa ipa info settings help
all: ipa

# Create build directory
prepare-build:
	@echo "Creating build directory..."
	@mkdir -p $(BUILD_DIR)

# Create export options plist for IPA generation
$(EXPORT_OPTIONS_PLIST): prepare-build
	@echo "Creating ExportOptions.plist..."
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>method</key>\n\t<string>development</string>\n\t<key>teamID</key>\n\t<string>K8Q74NT2BG</string>\n\t<key>compileBitcode</key>\n\t<false/>\n\t<key>uploadBitcode</key>\n\t<false/>\n\t<key>uploadSymbols</key>\n\t<true/>\n\t<key>signingStyle</key>\n\t<string>automatic</string>\n</dict>\n</plist>\n' > $(EXPORT_OPTIONS_PLIST)

# Clean build artifacts  
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@$(XCODEBUILD) -project $(PROJECT_FILE) -scheme "$(SCHEME_NAME)" clean

# Build the app for device
build-app: prepare-build
	@echo "Building $(PROJECT_NAME) for device..."
	@$(XCODEBUILD) \
		-project $(PROJECT_FILE) \
		-scheme "$(SCHEME_NAME)" \
		-configuration $(CONFIGURATION) \
		-destination "generic/platform=iOS" \
		-derivedDataPath $(BUILD_DIR)/DerivedData \
		CODE_SIGNING_ALLOWED=NO \
		build

# Archive the app
archive: prepare-build
	@echo "Archiving $(PROJECT_NAME)..."
	@$(XCODEBUILD) \
		-project $(PROJECT_FILE) \
		-scheme "$(SCHEME_NAME)" \
		-configuration $(CONFIGURATION) \
		-destination "generic/platform=iOS" \
		-archivePath "$(ARCHIVE_PATH)" \
		-derivedDataPath $(BUILD_DIR)/DerivedData \
		CODE_SIGNING_ALLOWED=NO \
		archive

# Export IPA from archive
export-ipa: archive $(EXPORT_OPTIONS_PLIST)
	@echo "Exporting IPA from archive..."
	@$(XCODEBUILD) \
		-exportArchive \
		-archivePath "$(ARCHIVE_PATH)" \
		-exportPath $(BUILD_DIR) \
		-exportOptionsPlist $(EXPORT_OPTIONS_PLIST)
	@echo "Renaming exported IPA..."
	@find $(BUILD_DIR) -name "*.ipa" -not -path "*/$(PROJECT_NAME).ipa" -exec mv {} $(IPA_PATH) \;

# Main target: Build and create IPA
ipa: export-ipa
	@echo "✅ IPA build completed successfully!"
	@echo "📦 Archive location: $(ARCHIVE_PATH)"
	@echo "📱 IPA location: $(IPA_PATH)"
	@ls -la $(IPA_PATH)

# Show project information
info:
	@echo "Project Information:"
	@$(XCODEBUILD) -list -project $(PROJECT_FILE)

# Show build settings
settings:
	@echo "Build Settings for $(SCHEME_NAME):"
	@$(XCODEBUILD) \
		-project $(PROJECT_FILE) \
		-scheme "$(SCHEME_NAME)" \
		-configuration $(CONFIGURATION) \
		-showBuildSettings

# Help target
help:
	@echo "Available targets:"
	@echo "  all       - Build and create IPA (default)"
	@echo "  build-app - Build the app for device"
	@echo "  archive   - Create .xcarchive"
	@echo "  export-ipa- Export IPA from archive"
	@echo "  ipa       - Complete build process (archive + export IPA)"
	@echo "  clean     - Clean build artifacts"
	@echo "  info      - Show project information"
	@echo "  settings  - Show build settings"
	@echo "  help      - Show this help message"
	@echo ""
	@echo "Output:"
	@echo "  Archive:  $(ARCHIVE_PATH)"
	@echo "  IPA:      $(IPA_PATH)"