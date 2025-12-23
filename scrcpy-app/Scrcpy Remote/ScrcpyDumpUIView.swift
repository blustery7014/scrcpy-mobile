//
//  ScrcpyDumpUIView.swift
//  Scrcpy Remote
//
//  UI dump view for displaying Android UI hierarchy from uiautomator dump
//

import UIKit

// MARK: - UI Element Model

@objc class DumpUIElement: NSObject {
    let bounds: CGRect
    let text: String?
    let resourceId: String?
    let className: String?
    let contentDesc: String?
    var children: [DumpUIElement] = []

    init(bounds: CGRect, text: String?, resourceId: String?, className: String?, contentDesc: String?) {
        self.bounds = bounds
        self.text = text
        self.resourceId = resourceId
        self.className = className
        self.contentDesc = contentDesc
        super.init()
    }

    var displayText: String {
        // Priority: text > content-desc > resource-id > class name
        if let text = text, !text.isEmpty {
            return text
        }
        if let contentDesc = contentDesc, !contentDesc.isEmpty {
            return contentDesc
        }
        if let resourceId = resourceId, !resourceId.isEmpty {
            // Extract last part of resource ID (e.g., "com.example:id/button" -> "button")
            if let lastPart = resourceId.split(separator: "/").last {
                return String(lastPart)
            }
            return resourceId
        }
        if let className = className, !className.isEmpty {
            // Extract simple class name (e.g., "android.widget.Button" -> "Button")
            if let lastPart = className.split(separator: ".").last {
                let simpleName = String(lastPart)
                // Skip generic container class names
                let skipClassNames = ["View", "ViewGroup"]
                if skipClassNames.contains(simpleName) {
                    return ""
                }
                return simpleName
            }
            return className
        }
        return ""
    }
}

// MARK: - XML Parser

class UIHierarchyParser: NSObject, XMLParserDelegate {
    private var elementStack: [DumpUIElement] = []
    private var rootElements: [DumpUIElement] = []
    private var screenBounds: CGRect = .zero

    func parse(xmlData: Data) -> (elements: [DumpUIElement], screenBounds: CGRect)? {
        let parser = XMLParser(data: xmlData)
        parser.delegate = self

        if parser.parse() {
            return (rootElements, screenBounds)
        }
        return nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        guard elementName == "node" else { return }

        let bounds = parseBounds(attributeDict["bounds"])
        let element = DumpUIElement(
            bounds: bounds,
            text: attributeDict["text"],
            resourceId: attributeDict["resource-id"],
            className: attributeDict["class"],
            contentDesc: attributeDict["content-desc"]
        )

        // Track screen bounds from the first element
        if screenBounds == .zero && bounds.width > 0 && bounds.height > 0 {
            screenBounds = bounds
        }

        elementStack.append(element)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "node", !elementStack.isEmpty else { return }

        let element = elementStack.removeLast()

        if elementStack.isEmpty {
            rootElements.append(element)
        } else {
            elementStack[elementStack.count - 1].children.append(element)
        }
    }

    private func parseBounds(_ boundsString: String?) -> CGRect {
        guard let boundsString = boundsString else { return .zero }

        // Parse bounds format: "[x1,y1][x2,y2]"
        let pattern = "\\[(\\d+),(\\d+)\\]\\[(\\d+),(\\d+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: boundsString, range: NSRange(boundsString.startIndex..., in: boundsString)) else {
            return .zero
        }

        let x1 = Int((boundsString as NSString).substring(with: match.range(at: 1))) ?? 0
        let y1 = Int((boundsString as NSString).substring(with: match.range(at: 2))) ?? 0
        let x2 = Int((boundsString as NSString).substring(with: match.range(at: 3))) ?? 0
        let y2 = Int((boundsString as NSString).substring(with: match.range(at: 4))) ?? 0

        return CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }
}

// MARK: - Pass-through Content View

/// A view that passes through touch events except for its subviews
class PassThroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        // Return nil if the hit view is self (pass through), otherwise return the hit view
        return hitView == self ? nil : hitView
    }
}

// MARK: - Dump UI View (UIKit)

@objc class ScrcpyDumpUIView: UIView {

    // MARK: - UI Components

    private let headerView = PassThroughView()
    private let refreshButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let contentView = PassThroughView()

    // MARK: - State

    private var isLoading = false
    private var elements: [DumpUIElement] = []
    private var screenBounds: CGRect = .zero
    private var remoteScreenSize: CGSize = .zero  // From adb shell wm size

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - Hit Test (Pass through touches except for interactive elements)

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Check if point is inside any of the interactive buttons
        let refreshPoint = convert(point, to: refreshButton)
        if refreshButton.bounds.contains(refreshPoint) && !refreshButton.isHidden && refreshButton.isEnabled {
            return refreshButton
        }

        let closePoint = convert(point, to: closeButton)
        if closeButton.bounds.contains(closePoint) && !closeButton.isHidden {
            return closeButton
        }

        let retryPoint = convert(point, to: retryButton)
        if retryButton.bounds.contains(retryPoint) && !retryButton.isHidden {
            return retryButton
        }

        // Pass through all other touches to views below (SDL view)
        return nil
    }

    // MARK: - Setup UI

    private func setupUI() {
        backgroundColor = .clear

        // Header view
        headerView.backgroundColor = .clear
        addSubview(headerView)

        // Refresh button with icon
        let refreshConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let refreshIcon = UIImage(systemName: "arrow.clockwise", withConfiguration: refreshConfig)
        refreshButton.setImage(refreshIcon, for: .normal)
        refreshButton.setTitle(" " + NSLocalizedString("Refresh", comment: ""), for: .normal)
        refreshButton.setTitleColor(.white, for: .normal)
        refreshButton.tintColor = .white
        refreshButton.backgroundColor = .systemBlue
        refreshButton.layer.cornerRadius = 18
        refreshButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        headerView.addSubview(refreshButton)

        // Loading indicator (inside refresh button)
        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true
        refreshButton.addSubview(loadingIndicator)

        // Close button - circular with black background and white border
        let closeConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        let closeImage = UIImage(systemName: "xmark", withConfiguration: closeConfig)
        closeButton.setImage(closeImage, for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = .black
        closeButton.layer.cornerRadius = 16 // Half of 32 to make perfect circle
        closeButton.layer.borderColor = UIColor.white.cgColor
        closeButton.layer.borderWidth = 1.5
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        headerView.addSubview(closeButton)

        // Loading label (centered) - hidden, not needed with transparent background
        loadingLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        loadingLabel.font = .systemFont(ofSize: 16)
        loadingLabel.textAlignment = .center
        loadingLabel.isHidden = true
        addSubview(loadingLabel)

        // Error label (centered)
        errorLabel.textColor = .white
        errorLabel.font = .systemFont(ofSize: 14)
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        errorLabel.layer.cornerRadius = 8
        errorLabel.clipsToBounds = true
        errorLabel.isHidden = true
        addSubview(errorLabel)

        // Retry button
        retryButton.setTitle(NSLocalizedString("Retry", comment: ""), for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.backgroundColor = .systemBlue
        retryButton.layer.cornerRadius = 18
        retryButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        retryButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        retryButton.isHidden = true
        addSubview(retryButton)

        // Content view for UI elements
        contentView.backgroundColor = .clear
        addSubview(contentView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let safeArea = safeAreaInsets
        let headerHeight: CGFloat = 56

        // Header
        headerView.frame = CGRect(x: 0, y: safeArea.top, width: bounds.width, height: headerHeight)

        // Center buttons together
        let buttonSpacing: CGFloat = 16
        let refreshButtonWidth: CGFloat = 140
        let refreshButtonHeight: CGFloat = 36
        let closeButtonSize: CGFloat = 32 // Square for perfect circle (36 - 10%)
        let totalButtonsWidth = refreshButtonWidth + buttonSpacing + closeButtonSize
        let buttonsStartX = (bounds.width - totalButtonsWidth) / 2

        // Vertically center both buttons in header
        let buttonY = (headerHeight - refreshButtonHeight) / 2
        let closeButtonY = (headerHeight - closeButtonSize) / 2

        // Refresh button (centered left)
        refreshButton.frame = CGRect(x: buttonsStartX, y: buttonY, width: refreshButtonWidth, height: refreshButtonHeight)

        // Loading indicator (inside refresh button, left side)
        loadingIndicator.frame = CGRect(x: 12, y: (refreshButtonHeight - 20) / 2, width: 20, height: 20)

        // Close button (centered right, next to refresh) - square for perfect circle
        closeButton.frame = CGRect(x: refreshButton.frame.maxX + buttonSpacing, y: closeButtonY, width: closeButtonSize, height: closeButtonSize)

        // Content view
        let contentY = headerView.frame.maxY
        let contentHeight = bounds.height - contentY - safeArea.bottom
        contentView.frame = CGRect(x: 0, y: contentY, width: bounds.width, height: contentHeight)

        // Loading label
        loadingLabel.frame = CGRect(x: 20, y: contentY + contentHeight / 2 - 20, width: bounds.width - 40, height: 40)

        // Error label
        errorLabel.frame = CGRect(x: 32, y: contentY + contentHeight / 2 - 60, width: bounds.width - 64, height: 80)

        // Retry button
        retryButton.frame = CGRect(x: (bounds.width - 100) / 2, y: errorLabel.frame.maxY + 16, width: 100, height: 36)

        // Re-render elements if we have them
        if !elements.isEmpty {
            renderElements()
        }
    }

    // MARK: - Actions

    @objc private func refreshTapped() {
        dumpUI()
    }

    @objc private func closeTapped() {
        hide()
    }

    // MARK: - Public Methods

    @objc func show() {
        guard let window = Self.activeWindow() else {
            print("❌ [ScrcpyDumpUIView] No active window found")
            return
        }

        frame = window.bounds
        alpha = 0

        window.addSubview(self)

        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            self.alpha = 1
        } completion: { _ in
            self.dumpUI()
        }

        print("📱 [ScrcpyDumpUIView] View shown")
    }

    @objc func hide() {
        UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseIn) {
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }

        print("📱 [ScrcpyDumpUIView] View hidden")
    }

    // MARK: - Dump Logic

    private func getDeviceSerial() -> String? {
        let connectionManager = SessionConnectionManager.shared
        guard let session = connectionManager.currentSession, session.deviceType == .adb else {
            print("❌ [ScrcpyDumpUIView] Cannot get ADB serial: no ADB session")
            return nil
        }

        // Use actual connection address if available (may be via Tailscale proxy)
        if connectionManager.isUsingTailscale,
           let host = connectionManager.actualHost,
           let port = connectionManager.actualPort {
            let serial = "\(host):\(port)"
            print("🔍 [ScrcpyDumpUIView] ADB device serial (via Tailscale): \(serial)")
            return serial
        }

        let serial = "\(session.hostReal):\(session.port)"
        print("🔍 [ScrcpyDumpUIView] ADB device serial: \(serial)")
        return serial
    }

    private func dumpUI() {
        guard let deviceSerial = getDeviceSerial() else {
            showError("No ADB device connected")
            return
        }

        setLoading(true, message: NSLocalizedString("Dumping...", comment: ""))

        let remotePath = "/data/local/tmp/scrcpy_remote_ui_dump.xml"
        let localPath = NSTemporaryDirectory() + "scrcpy_ui_dump.xml"

        // Step 0: Get remote screen size from wm size
        let wmSizeCommand = ["-s", deviceSerial, "shell", "wm", "size"]

        print("📱 [ScrcpyDumpUIView] Getting remote screen size...")

        ADBClient.shared().executeADBCommandAsync(wmSizeCommand) { [weak self] output, returnCode in
            guard let self = self else { return }

            if returnCode == 0, let output = output {
                self.parseWmSizeOutput(output)
            } else {
                print("⚠️ [ScrcpyDumpUIView] Failed to get wm size, will use fallback")
            }

            // Step 1: Execute uiautomator dump
            let dumpCommand = ["-s", deviceSerial, "shell", "uiautomator", "dump", remotePath]

            print("📱 [ScrcpyDumpUIView] Executing uiautomator dump on device: \(deviceSerial)")

            ADBClient.shared().executeADBCommandAsync(dumpCommand) { [weak self] output, returnCode in
                guard let self = self else { return }

                if returnCode != 0 {
                    DispatchQueue.main.async {
                        self.showError("Failed to dump UI: \(output ?? "Unknown error")")
                    }
                    return
                }

                print("📱 [ScrcpyDumpUIView] Dump successful, pulling file...")

                DispatchQueue.main.async {
                    self.setLoading(true, message: NSLocalizedString("Downloading...", comment: ""))
                }

                // Step 2: Pull the file
                let pullCommand = ["-s", deviceSerial, "pull", remotePath, localPath]

                ADBClient.shared().executeADBCommandAsync(pullCommand) { [weak self] output, returnCode in
                    guard let self = self else { return }

                    if returnCode != 0 {
                        DispatchQueue.main.async {
                            self.showError("Failed to pull dump file: \(output ?? "Unknown error")")
                        }
                        return
                    }

                    print("📱 [ScrcpyDumpUIView] File pulled, parsing XML...")

                    DispatchQueue.main.async {
                        self.setLoading(true, message: NSLocalizedString("Parsing...", comment: ""))
                    }

                    self.parseXMLFile(at: localPath)
                }
            }
        }
    }

    /// Parse wm size output to get remote screen size
    /// Format:
    /// Physical size: 1080x2340
    /// Override size: 1206x2622
    private func parseWmSizeOutput(_ output: String) {
        var physicalSize: CGSize = .zero
        var overrideSize: CGSize = .zero

        let lines = output.components(separatedBy: "\n")
        for line in lines {
            if line.contains("Override size:") {
                if let size = parseSizeFromLine(line) {
                    overrideSize = size
                    print("📱 [ScrcpyDumpUIView] Override size: \(size)")
                }
            } else if line.contains("Physical size:") {
                if let size = parseSizeFromLine(line) {
                    physicalSize = size
                    print("📱 [ScrcpyDumpUIView] Physical size: \(size)")
                }
            }
        }

        // Prefer override size, fallback to physical size
        if overrideSize.width > 0 && overrideSize.height > 0 {
            remoteScreenSize = overrideSize
        } else if physicalSize.width > 0 && physicalSize.height > 0 {
            remoteScreenSize = physicalSize
        }

        print("📱 [ScrcpyDumpUIView] Using remote screen size: \(remoteScreenSize)")
    }

    /// Parse size from line like "Physical size: 1080x2340"
    private func parseSizeFromLine(_ line: String) -> CGSize? {
        let pattern = "(\\d+)x(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        let widthStr = (line as NSString).substring(with: match.range(at: 1))
        let heightStr = (line as NSString).substring(with: match.range(at: 2))

        guard let width = Double(widthStr), let height = Double(heightStr) else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    private func parseXMLFile(at path: String) {
        guard let data = FileManager.default.contents(atPath: path) else {
            DispatchQueue.main.async {
                self.showError("Failed to read dump file")
            }
            return
        }

        let parser = UIHierarchyParser()
        if let result = parser.parse(xmlData: data) {
            DispatchQueue.main.async {
                self.elements = result.elements
                self.screenBounds = result.screenBounds
                self.setLoading(false, message: nil)
                self.renderElements()
                print("📱 [ScrcpyDumpUIView] Parsed \(result.elements.count) root elements, screen bounds: \(result.screenBounds)")
            }
        } else {
            DispatchQueue.main.async {
                self.showError("Failed to parse XML file")
            }
        }
    }

    // MARK: - UI State

    private func setLoading(_ loading: Bool, message: String?) {
        isLoading = loading

        if loading {
            // Show loading indicator inside button with shorter text
            loadingIndicator.startAnimating()
            refreshButton.setImage(nil, for: .normal)
            refreshButton.setTitle(message ?? NSLocalizedString("Dumping...", comment: ""), for: .normal)
            refreshButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 0)
            // Use darker blue for disabled state instead of gray
            refreshButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.5)
            refreshButton.isEnabled = false
            errorLabel.isHidden = true
            retryButton.isHidden = true
            // Keep previous elements visible during refresh
        } else {
            loadingIndicator.stopAnimating()
            // Restore refresh icon
            let refreshConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            let refreshIcon = UIImage(systemName: "arrow.clockwise", withConfiguration: refreshConfig)
            refreshButton.setImage(refreshIcon, for: .normal)
            refreshButton.setTitle(" " + NSLocalizedString("Refresh", comment: ""), for: .normal)
            refreshButton.titleEdgeInsets = .zero
            refreshButton.backgroundColor = .systemBlue
            refreshButton.isEnabled = true
        }
    }

    private func showError(_ message: String) {
        setLoading(false, message: nil)
        errorLabel.text = message
        errorLabel.isHidden = false
        retryButton.isHidden = false
    }

    // MARK: - Get Actual Render Rect

    /// Get the actual render rect where the scrcpy video is displayed
    /// This matches the AVLayerVideoGravityResizeAspect behavior
    /// The returned rect is in contentView's coordinate space
    private func getScrcpyRenderRect() -> CGRect? {
        // Try to get remote frame dimensions from ScrcpyRuntime first
        var frameWidth: Int32 = 0
        var frameHeight: Int32 = 0
        _ = GetCurrentRemoteOrientation(&frameWidth, &frameHeight)

        // If not available from ScrcpyRuntime, use remoteScreenSize from wm size
        var remoteWidth = CGFloat(frameWidth)
        var remoteHeight = CGFloat(frameHeight)

        if remoteWidth <= 0 || remoteHeight <= 0 {
            if remoteScreenSize.width > 0 && remoteScreenSize.height > 0 {
                remoteWidth = remoteScreenSize.width
                remoteHeight = remoteScreenSize.height
                print("📱 [ScrcpyDumpUIView] Using wm size for render rect: \(remoteScreenSize)")
            } else {
                print("⚠️ [ScrcpyDumpUIView] Remote frame dimensions not available")
                return nil
            }
        }

        // SDL renders in the full window, so use self.bounds (full screen)
        // But we need to map to contentView's coordinate space
        let viewBounds = bounds
        let contentOrigin = contentView.frame.origin

        let videoAspect = remoteWidth / remoteHeight
        let viewAspect = viewBounds.width / viewBounds.height

        var renderRect: CGRect

        if videoAspect > viewAspect {
            // Video is wider - fit to width, letterbox top/bottom
            let renderWidth = viewBounds.width
            let renderHeight = renderWidth / videoAspect
            let offsetY = (viewBounds.height - renderHeight) / 2
            renderRect = CGRect(x: 0, y: offsetY, width: renderWidth, height: renderHeight)
        } else {
            // Video is taller - fit to height, pillarbox left/right
            let renderHeight = viewBounds.height
            let renderWidth = renderHeight * videoAspect
            let offsetX = (viewBounds.width - renderWidth) / 2
            renderRect = CGRect(x: offsetX, y: 0, width: renderWidth, height: renderHeight)
        }

        // Convert to contentView's coordinate space
        renderRect.origin.x -= contentOrigin.x
        renderRect.origin.y -= contentOrigin.y

        print("📱 [ScrcpyDumpUIView] Frame: \(remoteWidth)x\(remoteHeight), View: \(viewBounds.size), Render rect in contentView: \(renderRect)")
        return renderRect
    }

    // MARK: - Render Elements

    private func renderElements() {
        // Clear previous
        contentView.subviews.forEach { $0.removeFromSuperview() }

        guard screenBounds.width > 0, screenBounds.height > 0 else {
            print("⚠️ [ScrcpyDumpUIView] Invalid screen bounds from XML")
            return
        }

        // Get the actual render rect where scrcpy displays the video
        guard let renderRect = getScrcpyRenderRect() else {
            print("⚠️ [ScrcpyDumpUIView] Could not get render rect, falling back to content bounds")
            renderElementsFallback()
            return
        }

        // Use remoteScreenSize from wm size, fallback to screenBounds if not available
        let remoteSize: CGSize
        if remoteScreenSize.width > 0 && remoteScreenSize.height > 0 {
            remoteSize = remoteScreenSize
        } else {
            // Fallback: use the most outside bounds from dumped XML
            remoteSize = CGSize(width: screenBounds.maxX, height: screenBounds.maxY)
            print("⚠️ [ScrcpyDumpUIView] Using fallback remote size from screenBounds: \(remoteSize)")
        }

        let localRenderSize = CGSize(width: renderRect.width, height: renderRect.height)

        // Step 1: Normalize dumped bounds based on remote screen size (0.0 - 1.0)
        let normalizedX = screenBounds.origin.x / remoteSize.width
        let normalizedY = screenBounds.origin.y / remoteSize.height
        let normalizedWidth = screenBounds.width / remoteSize.width
        let normalizedHeight = screenBounds.height / remoteSize.height

        // Step 2: Calculate scale factor based on local render size and remote screen size
        let scaleW = localRenderSize.width / remoteSize.width
        let scaleH = localRenderSize.height / remoteSize.height
        let scale = min(scaleW, scaleH)

        // Step 3: Calculate the local rendered screen size
        let localRenderedWidth = remoteSize.width * scale
        let localRenderedHeight = remoteSize.height * scale

        // Step 4: Calculate center offset to render in center of local view
        let centerOffsetX = renderRect.origin.x + (localRenderSize.width - localRenderedWidth) / 2
        let centerOffsetY = renderRect.origin.y + (localRenderSize.height - localRenderedHeight) / 2

        // Step 5: Calculate offset for element positions
        // Element positions are absolute in remote screen coordinates
        let offsetX = centerOffsetX
        let offsetY = centerOffsetY

        print("📱 [ScrcpyDumpUIView] Remote screen: \(remoteSize), Local render: \(localRenderSize)")
        print("📱 [ScrcpyDumpUIView] Normalized bounds: (x:\(normalizedX), y:\(normalizedY), w:\(normalizedWidth), h:\(normalizedHeight))")
        print("📱 [ScrcpyDumpUIView] Scale: \(scale), Local rendered size: (\(localRenderedWidth), \(localRenderedHeight))")
        print("📱 [ScrcpyDumpUIView] Center offset: (\(centerOffsetX), \(centerOffsetY))")

        // Render elements recursively
        for element in elements {
            renderElement(element, scale: scale, offset: CGPoint(x: offsetX, y: offsetY))
        }

        // Bring header view to front so buttons are always on top
        bringSubviewToFront(headerView)

        print("📱 [ScrcpyDumpUIView] Rendered elements with scale: \(scale), offset: (\(offsetX), \(offsetY)), dumped: \(screenBounds.size)")
    }

    /// Fallback rendering when scrcpy render rect is not available
    private func renderElementsFallback() {
        let availableSize = contentView.bounds.size
        guard availableSize.width > 0, availableSize.height > 0 else { return }

        // Calculate scale to fit
        let scaleX = availableSize.width / screenBounds.width
        let scaleY = availableSize.height / screenBounds.height
        let scale = min(scaleX, scaleY) * 0.95

        // Calculate offset to center
        let scaledWidth = screenBounds.width * scale
        let scaledHeight = screenBounds.height * scale
        let offsetX = (availableSize.width - scaledWidth) / 2 - screenBounds.origin.x * scale
        let offsetY = (availableSize.height - scaledHeight) / 2 - screenBounds.origin.y * scale

        for element in elements {
            renderElement(element, scale: scale, offset: CGPoint(x: offsetX, y: offsetY))
        }

        print("📱 [ScrcpyDumpUIView] Rendered elements (fallback) with scale: \(scale)")
    }

    private func renderElement(_ element: DumpUIElement, scale: CGFloat, offset: CGPoint) {
        let scaledBounds = CGRect(
            x: element.bounds.origin.x * scale + offset.x,
            y: element.bounds.origin.y * scale + offset.y,
            width: element.bounds.width * scale,
            height: element.bounds.height * scale
        )

        // Only render if bounds are valid and visible
        guard scaledBounds.width > 2, scaledBounds.height > 2 else {
            // Still render children
            for child in element.children {
                renderElement(child, scale: scale, offset: offset)
            }
            return
        }

        // Element border view
        let borderView = UIView(frame: scaledBounds)
        borderView.layer.borderColor = UIColor.green.withAlphaComponent(0.6).cgColor
        borderView.layer.borderWidth = 1
        borderView.backgroundColor = .clear
        borderView.isUserInteractionEnabled = false
        contentView.addSubview(borderView)

        // Add label if element has display text and is large enough
        let displayText = element.displayText
        if !displayText.isEmpty && scaledBounds.width > 20 && scaledBounds.height > 12 {
            let label = UILabel()
            label.text = displayText
            label.textColor = .white
            label.textAlignment = .center
            label.backgroundColor = UIColor.black.withAlphaComponent(0.8)
            label.clipsToBounds = true
            label.lineBreakMode = .byTruncatingTail
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.5

            // Start with desired font size, will scale down if needed
            let maxFontSize: CGFloat = min(12, scaledBounds.height * 0.6)
            label.font = .systemFont(ofSize: maxFontSize)

            // Size to fit, but constrain to bounds
            label.sizeToFit()
            var labelFrame = label.frame
            let horizontalPadding: CGFloat = 12
            let verticalPadding: CGFloat = 4
            labelFrame.size.width = min(labelFrame.width + horizontalPadding, scaledBounds.width - 4)
            labelFrame.size.height = min(labelFrame.height + verticalPadding, scaledBounds.height - 2)
            label.frame = labelFrame

            // Capsule shape: corner radius = half of height
            label.layer.cornerRadius = labelFrame.height / 2

            // Center in element
            label.center = CGPoint(x: scaledBounds.midX, y: scaledBounds.midY)
            contentView.addSubview(label)
        }

        // Render children
        for child in element.children {
            renderElement(child, scale: scale, offset: offset)
        }
    }

    // MARK: - Helper

    private static func activeWindow() -> UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene,
               windowScene.activationState == .foregroundActive {
                for window in windowScene.windows {
                    if window.isKeyWindow {
                        return window
                    }
                }
                return windowScene.windows.first
            }
        }
        return nil
    }
}

// MARK: - Presenter for Objective-C

@objc class ScrcpyDumpUIPresenter: NSObject {
    @objc static func show() {
        DispatchQueue.main.async {
            let dumpView = ScrcpyDumpUIView()
            dumpView.show()
        }
    }
}
