import SwiftUI
import AppKit
import AVKit
import SwiftData
import AppKit
import AVFoundation
import CoreAudio
import CoreImage
import ScreenCaptureKit
import IOKit.ps

// MARK: - Data Model
@Model
class WallpaperSettings {
    var lastUsedPath: String?
    var autoStart: Bool
    var playbackMode: PlaybackMode
    var adaptiveMenuBar: Bool
    var thumbnailData: Data?
    var batteryLimitEnabled: Bool
    var batteryLimitPercentage: Double
    
    init(lastUsedPath: String? = nil, autoStart: Bool = false, playbackMode: PlaybackMode = .loop, adaptiveMenuBar: Bool = true, thumbnailData: Data? = nil, batteryLimitEnabled: Bool = false, batteryLimitPercentage: Double = 20) {
        self.lastUsedPath = lastUsedPath
        self.autoStart = autoStart
        self.playbackMode = playbackMode
        self.adaptiveMenuBar = adaptiveMenuBar
        self.thumbnailData = thumbnailData
        self.batteryLimitEnabled = batteryLimitEnabled
        self.batteryLimitPercentage = batteryLimitPercentage
    }
    
    enum PlaybackMode: String, Codable {
        case loop, shuffle, once
    }
}

// MARK: - Battery Monitor
class BatteryMonitor {
    static let shared = BatteryMonitor()
    private var timer: Timer?
    var onBatteryLevelChanged: ((Double, Bool) -> Void)?
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkBatteryStatus()
        }
        timer?.fire() // Initial check
    }
    
    private func checkBatteryStatus() {
        if let powerSource = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(powerSource)?.takeRetainedValue() as? [CFTypeRef] {
            
            let callback = onBatteryLevelChanged // Capture the callback locally
            
            for source in sources {
                if let description = IOPSGetPowerSourceDescription(powerSource, source)?.takeUnretainedValue() as? [String: Any] {
                    let isCharging = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
                    let batteryLevel = Double(description[kIOPSCurrentCapacityKey] as? Int ?? 100)
                    let percentage = batteryLevel
                    
                    DispatchQueue.main.async {
                        callback?(percentage, isCharging)
                    }
                }
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}



// MARK: - Persistence Manager
class PersistenceManager {
    static let shared = PersistenceManager()
    
    private init() {}
    
    func createContainer() -> ModelContainer {
        let schema = Schema([WallpaperSettings.self])
        
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolderURL = appSupportURL.appendingPathComponent("LiveWallpaper", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: appFolderURL, withIntermediateDirectories: true)
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: appFolderURL.appendingPathComponent("WallpaperSettings.store"),
            allowsSave: true
        )
        
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<WallpaperSettings>()
            
            if let existingSettings = try? context.fetch(descriptor),
               existingSettings.isEmpty {
                let defaultSettings = WallpaperSettings()
                context.insert(defaultSettings)
                try? context.save()
            }
            
            return container
        } catch {
            print("Error creating persistent container: \(error.localizedDescription)")
            return try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
    }
}

// MARK: - Color Sampling Manager
class ColorSamplingManager {
    static let shared = ColorSamplingManager()
    
    private init() {}
    
    func getDominantColor(from image: NSImage) -> NSColor {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .systemBlue
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        
        var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return .systemBlue
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var totalRed = 0
        var totalGreen = 0
        var totalBlue = 0
        var totalPixels = 0
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let alpha = CGFloat(rawData[offset + 3]) / 255.0
                
                if alpha > 0.1 {
                    totalRed += Int(rawData[offset])
                    totalGreen += Int(rawData[offset + 1])
                    totalBlue += Int(rawData[offset + 2])
                    totalPixels += 1
                }
            }
        }
        
        guard totalPixels > 0 else {
            return .systemBlue
        }
        
        let averageRed = CGFloat(totalRed) / CGFloat(totalPixels) / 255.0
        let averageGreen = CGFloat(totalGreen) / CGFloat(totalPixels) / 255.0
        let averageBlue = CGFloat(totalBlue) / CGFloat(totalPixels) / 255.0
        
        return NSColor(red: averageRed, green: averageGreen, blue: averageBlue, alpha: 1.0)
    }
}

// MARK: - Model Manager
class ModelManager: ObservableObject {
    static let shared = ModelManager()
    @Published var settings: WallpaperSettings?
    private var modelContext: ModelContext?
    
    private init() {}
    
    func initialize(with context: ModelContext) {
        self.modelContext = context
        loadSettings()
    }
    
    func loadSettings() {
        let descriptor = FetchDescriptor<WallpaperSettings>()
        
        do {
            let results = try modelContext?.fetch(descriptor)
            settings = results?.first ?? createDefaultSettings()
        } catch {
            print("Error loading settings: \(error.localizedDescription)")
            settings = createDefaultSettings()
        }
    }
    
    private func createDefaultSettings() -> WallpaperSettings {
        let newSettings = WallpaperSettings()
        modelContext?.insert(newSettings)
        try? modelContext?.save()
        return newSettings
    }
    
    func updateSettings() {
        try? modelContext?.save()
    }
}

// MARK: - Menu Bar Controller
class MenuBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    @Published var isPlaying = false
    
    init() {
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "Live Wallpaper")
            
            // Create and configure drag view
            let dragView = DraggableView(frame: button.bounds)
            dragView.autoresizingMask = [.width, .height]
            button.addSubview(dragView)
        }
    }
    
    func updateIcon(isPlaying: Bool, color: NSColor? = nil) {
        self.isPlaying = isPlaying
        let imageName = isPlaying ? "pause.circle.fill" : "play.circle.fill"
        if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: "Playback Status") {
            statusItem?.button?.image = image
            if let color = color {
                statusItem?.button?.contentTintColor = color
            }
        }
    }
}

// MARK: - Draggable View
class DraggableView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let types = sender.draggingPasteboard.types ?? []
        if types.contains(.fileURL) {
            return .copy
        }
        return []
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let url = urls.first else {
            return false
        }
        
        let supportedTypes = ["mp4", "mov", "m4v"]
        if supportedTypes.contains(url.pathExtension.lowercased()) {
            // Post notification when video is dropped
            NotificationCenter.default.post(name: NSNotification.Name("VideoDropped"), object: url)
            return true
        }
        return false
    }
}

// MARK: - Window Manager
class WallpaperWindowManager: ObservableObject {
    private var window: NSWindow?
    private var playerView: AVPlayerView?
    private var player: AVPlayer?
    private var menuBarController: MenuBarController
    private let colorSamplingManager = ColorSamplingManager.shared
    private let batteryMonitor = BatteryMonitor.shared
    
    @Published var isPlaying: Bool = false {
        didSet {
            if isPlaying {
                startColorSampling()
            } else {
                stopColorSampling()
                menuBarController.updateIcon(isPlaying: false)
            }
        }
    }
    
    init(menuBarController: MenuBarController) {
        self.menuBarController = menuBarController
        setupWindow()
        setupBatteryMonitoring()
    }
    
    private func setupBatteryMonitoring() {
        batteryMonitor.onBatteryLevelChanged = { [weak self] batteryLevel, isCharging in
            guard let self = self,
                  let settings = ModelManager.shared.settings,
                  settings.batteryLimitEnabled else { return }
            
            if !isCharging && batteryLevel <= settings.batteryLimitPercentage && self.isPlaying {
                DispatchQueue.main.async {
                    self.stop()
                }
            }
        }
    }
    
    private func setupWindow() {
        guard let screen = NSScreen.main else { return }
        
        class BackgroundWindow: NSWindow {
            override var canBecomeKey: Bool { return false }
            override var canBecomeMain: Bool { return false }
        }
        
        window = BackgroundWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        configureWindow()
        setupPlayerView()
    }
    
    private func configureWindow() {
        window?.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window?.backgroundColor = .clear
        window?.isOpaque = false
        window?.hasShadow = false
        window?.ignoresMouseEvents = true
        window?.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window?.isExcludedFromWindowsMenu = true
        window?.tabbingMode = .disallowed
    }
    
    private func setupPlayerView() {
        playerView = AVPlayerView()
        playerView?.controlsStyle = .none
        playerView?.videoGravity = .resizeAspectFill
        playerView?.allowsPictureInPicturePlayback = false
        window?.contentView = playerView
    }
    
    private func startColorSampling() {
        guard let playerView = playerView,
              ModelManager.shared.settings?.adaptiveMenuBar == true else {
            menuBarController.updateIcon(isPlaying: true)
            return
        }
        
        if let currentItem = player?.currentItem {
            let imageGenerator = AVAssetImageGenerator(asset: currentItem.asset)
            imageGenerator.appliesPreferredTrackTransform = true
            
            Task {
                do {
                    let time = CMTime(seconds: 0, preferredTimescale: 600)
                    let cgImage = try await imageGenerator.image(at: time).image
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 100, height: 100))
                    
                    let dominantColor = ColorSamplingManager.shared.getDominantColor(from: nsImage)
                    await MainActor.run {
                        self.menuBarController.updateIcon(isPlaying: true, color: dominantColor)
                    }
                } catch {
                    print("Error generating thumbnail for color sampling: \(error)")
                    await MainActor.run {
                        self.menuBarController.updateIcon(isPlaying: true)
                    }
                }
            }
        }
    }
    
    private func stopColorSampling() {
        menuBarController.updateIcon(isPlaying: false)
    }
    
    func setVideo(url: URL) {
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        configureAudioSettings(for: playerItem, with: asset)
        setupPlayer(with: playerItem)
    }
    
    private func configureAudioSettings(for playerItem: AVPlayerItem, with asset: AVAsset) {
        Task {
            do {
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                
                if let audioTrack = audioTracks.first {
                    await MainActor.run {
                        let audioMix = AVMutableAudioMix()
                        let audioInputParameters = AVMutableAudioMixInputParameters(track: audioTrack)
                        audioInputParameters.setVolume(0, at: .zero)
                        audioMix.inputParameters = [audioInputParameters]
                        playerItem.audioMix = audioMix
                    }
                }
            } catch {
                print("Error loading audio tracks: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupPlayer(with playerItem: AVPlayerItem) {
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
            player?.isMuted = true
            playerView?.player = player
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        
        player?.allowsExternalPlayback = false
        setupLooping(for: playerItem)
    }
    
    private func setupLooping(for playerItem: AVPlayerItem) {
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }
    }
    
    func start() {
        window?.orderFront(nil)
        player?.play()
        isPlaying = true
    }
    
    func stop() {
        player?.pause()
        window?.orderOut(nil)
        isPlaying = false
    }
    
    func cleanup() {
        stopColorSampling()
        player?.pause()
        player = nil
        window?.close()
        window = nil
    }
}

// MARK: - Preview Player Manager
@MainActor
class PreviewPlayerManager: ObservableObject {
    @Published private(set) var previewImage: NSImage?
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    
    nonisolated func setupPreview(url: URL, completion: @escaping ((Data?) -> Void)) {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        Task { [weak self] in
            do {
                let time = CMTime(seconds: 0, preferredTimescale: 600)
                let cgImage = try await imageGenerator.image(at: time).image
                
                // Convert CGImage to Data before sending across actor boundary
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 280, height: 158))
                let imageData: Data? = {
                    if let tiffData = nsImage.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData) {
                        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
                    }
                    return nil
                }()
                
                await MainActor.run { [weak self] in
                    if let imageData = imageData {
                        self?.previewImage = NSImage(data: imageData)
                    }
                    completion(imageData)
                }
            } catch {
                print("Could not generate thumbnail: \(error)")
                await MainActor.run { [weak self] in
                    self?.previewImage = nil
                    completion(nil)
                }
            }
        }
        
        Task { @MainActor [weak self] in
            self?.cleanup()
        }
    }
    
    func setPreviewFromData(_ data: Data?) {
        guard let data = data else {
            previewImage = nil
            return
        }
        
        if let nsImage = NSImage(data: data) {
            previewImage = nsImage
        }
    }
    
    private func cleanup() {
        player?.pause()
        player = nil
        playerLayer = nil
        videoOutput = nil
    }
}

// MARK: - Custom Button Styles
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.controlActiveState) private var controlActiveState
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor)
                    .opacity(configuration.isPressed ? 0.8 : 1)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
            )
            .foregroundColor(.white)
            .font(.system(size: 14, weight: .medium))
            .opacity(controlActiveState == .inactive ? 0.5 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct QuitButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
            )
            .foregroundColor(Color.red)
            .font(.system(size: 14, weight: .medium))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Content View
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var windowManager: WallpaperWindowManager
    @ObservedObject private var modelManager = ModelManager.shared
    @StateObject private var previewManager = PreviewPlayerManager()
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDragging = false
    
    private let folderName = "Live Wallpaper Videos"
    
    init(menuBarController: MenuBarController) {
        self._windowManager = ObservedObject(wrappedValue: WallpaperWindowManager(menuBarController: menuBarController))
        createVideoFolder()
        
        // Store self in a local variable to avoid capture
        let manager = ModelManager.shared
        let preview = PreviewPlayerManager()
        let window = WallpaperWindowManager(menuBarController: menuBarController)
        self._previewManager = StateObject(wrappedValue: preview)
        self._windowManager = ObservedObject(wrappedValue: window)
        
        // Observe video drop notification
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("VideoDropped"),
            object: nil,
            queue: .main
        ) { notification in
            guard let url = notification.object as? URL else { return }
            
            let folder = ContentView.getVideoFolderURL()
            if let destinationURL = ContentView.copyVideoToFolder(from: url, to: folder, oldPath: manager.settings?.lastUsedPath) {
                manager.settings?.lastUsedPath = destinationURL.path
                manager.settings?.autoStart = true
                preview.setupPreview(url: destinationURL) { thumbnailData in
                    manager.settings?.thumbnailData = thumbnailData
                    manager.updateSettings()
                }
                window.setVideo(url: destinationURL)
                window.start()
            }
        }
    }
    
    // Make these static to avoid self capture
    private static func getVideoFolderURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Live Wallpaper Videos")
    }
    
    private static func copyVideoToFolder(from sourceURL: URL, to folderURL: URL?, oldPath: String?) -> URL? {
        guard let folderURL = folderURL else { return nil }
        
        // First, clean up any existing video in the folder
        if let oldPath = oldPath {
            let oldURL = URL(fileURLWithPath: oldPath)
            if FileManager.default.fileExists(atPath: oldURL.path) {
                try? FileManager.default.removeItem(at: oldURL)
            }
        }
        
        // Also clean up any other files that might be in the folder
        if let contents = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) {
            for file in contents {
                try? FileManager.default.removeItem(at: file)
            }
        }
        
        // Create a unique filename using UUID
        let fileExtension = sourceURL.pathExtension
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = folderURL.appendingPathComponent(fileName)
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            print("Error copying video: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func createVideoFolder() {
        guard let folderURL = ContentView.getVideoFolderURL() else { return }
        
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try? FileManager.default.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
    
    private func handleDroppedVideo(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        
        let manager = modelManager
        let preview = previewManager
        let window = windowManager
        
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { item, error in
                guard let url = item as? URL else { return }
                
                DispatchQueue.main.async {
                    let folder = ContentView.getVideoFolderURL()
                    if let destinationURL = ContentView.copyVideoToFolder(from: url, to: folder, oldPath: manager.settings?.lastUsedPath) {
                        manager.settings?.lastUsedPath = destinationURL.path
                        manager.settings?.autoStart = true
                        preview.setupPreview(url: destinationURL) { thumbnailData in
                            manager.settings?.thumbnailData = thumbnailData
                            manager.updateSettings()
                        }
                        window.setVideo(url: destinationURL)
                        window.start()
                    }
                }
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Live Wallpaper")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 12)
            
            // Preview Section with Drag and Drop
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isDragging ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: isDragging ? 2 : 1)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
                    .frame(height: 180)
                
                Group {
                    if let previewImage = previewManager.previewImage {
                        Image(nsImage: previewImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 300, maxHeight: 180)
                            .cornerRadius(12)
                            .transition(.opacity)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: isDragging ? "arrow.down.circle" : "photo.fill")
                                .font(.system(size: 36))
                                .foregroundColor(isDragging ? .accentColor : .gray.opacity(0.7))
                            Text(isDragging ? "Drop video here" : "No wallpaper selected")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(isDragging ? .accentColor : .gray)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .onDrop(of: [.movie], isTargeted: $isDragging) { providers in
                handleDroppedVideo(providers: providers)
                return true
            }
            
            // Action Buttons
            HStack(spacing: 16) {
                Button(action: chooseVideo) {
                    Label("Choose Video", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AccentButtonStyle())
                
                Button(action: togglePlayback) {
                    Label(
                        windowManager.isPlaying ? "Stop" : "Start",
                        systemImage: windowManager.isPlaying ? "stop.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(AccentButtonStyle())
            }
            .padding(.horizontal)
            
            // Settings Section
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
                
                VStack(spacing: 12) {
                    Toggle("Auto-start on launch", isOn: Binding(
                        get: { modelManager.settings?.autoStart ?? false },
                        set: { updateAutoStart($0) }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    
                    Toggle("Adaptive menu bar color", isOn: Binding(
                        get: { modelManager.settings?.adaptiveMenuBar ?? true },
                        set: { updateAdaptiveMenuBar($0) }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    
                    Toggle("Stop when battery is low", isOn: Binding(
                        get: { modelManager.settings?.batteryLimitEnabled ?? false },
                        set: { updateBatteryLimit($0) }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    
                    if modelManager.settings?.batteryLimitEnabled == true {
                        HStack(spacing: 12) {
                            Text("\(Int(modelManager.settings?.batteryLimitPercentage ?? 20))%")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 45, alignment: .trailing)
                                .padding(.leading, 4)
                            
                            Slider(value: Binding(
                                get: { modelManager.settings?.batteryLimitPercentage ?? 20 },
                                set: { updateBatteryLimitPercentage($0) }
                            ), in: 10...80, step: 5)
                            .accentColor(.red)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.red.opacity(0.1))
                                    .padding(.horizontal, -8)
                                    .padding(.vertical, -4)
                            )
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal)
            
            Divider()
                .padding(.vertical, 8)
            
            // Footer
            VStack(spacing: 8) {
                Button("Quit Application") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(QuitButtonStyle())
                
                VStack(spacing: 4) {
                    Text("Version 1.0.0")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 12)
            }
        }
        .frame(width: 340)
        .onAppear {
            modelManager.initialize(with: modelContext)
            handleOnAppear()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: modelManager.settings?.batteryLimitEnabled)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
    }
    
    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                modelManager.settings?.lastUsedPath = url.absoluteString
                modelManager.settings?.autoStart = true  // Enable auto-start when video is selected
                previewManager.setupPreview(url: url) { thumbnailData in
                    modelManager.settings?.thumbnailData = thumbnailData
                    modelManager.updateSettings()
                }
                windowManager.setVideo(url: url)
                windowManager.start()
            }
        }
    }
    
    private func handleOnAppear() {
        previewManager.setPreviewFromData(modelManager.settings?.thumbnailData)
        
        // Try to auto-start if there's a saved video path.
        // Modified to auto-start regardless of the autoStart flag.
        if let path = modelManager.settings?.lastUsedPath,
           let url = URL(string: path) {
            windowManager.setVideo(url: url)
            windowManager.start()
        }
    }
    
    private func togglePlayback() {
        if windowManager.isPlaying {
            windowManager.stop()
        } else if let path = modelManager.settings?.lastUsedPath {
            let fileURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                windowManager.setVideo(url: fileURL)
                windowManager.start()
            }
        }
    }
    
    private func updateAutoStart(_ value: Bool) {
        modelManager.settings?.autoStart = value
        modelManager.updateSettings()
    }
    
    private func updateAdaptiveMenuBar(_ value: Bool) {
        modelManager.settings?.adaptiveMenuBar = value
        modelManager.updateSettings()
    }
    
    private func updateBatteryLimit(_ value: Bool) {
        modelManager.settings?.batteryLimitEnabled = value
        modelManager.updateSettings()
    }
    
    private func updateBatteryLimitPercentage(_ value: Double) {
        modelManager.settings?.batteryLimitPercentage = value
        modelManager.updateSettings()
    }
}

// MARK: - Main Scene
struct MainScene: Scene {
    @StateObject private var menuBarController = MenuBarController()
    @ObservedObject private var windowManager: WallpaperWindowManager
    @ObservedObject private var modelManager = ModelManager.shared
    let modelContainer: ModelContainer
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let controller = MenuBarController()
        _menuBarController = StateObject(wrappedValue: controller)
        _windowManager = ObservedObject(wrappedValue: WallpaperWindowManager(menuBarController: controller))
        
        // Initialize model manager with context
        let context = ModelContext(modelContainer)
        ModelManager.shared.initialize(with: context)
        
        // Check for auto-start path
        if let path = ModelManager.shared.settings?.lastUsedPath,
           ModelManager.shared.settings?.autoStart == true {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                let manager = WallpaperWindowManager(menuBarController: controller)
                manager.setVideo(url: url)
                manager.start()
                _windowManager = ObservedObject(wrappedValue: manager)
            }
        }
    }
    
    var body: some Scene {
        MenuBarExtra {
            ContentView(menuBarController: menuBarController)
                .modelContainer(modelContainer)
                .frame(width: 340)
        } label: {
            Image(systemName: "gearshape.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App Entry Point
@main
struct LiveWallpaperApp: App {
    let modelContainer: ModelContainer
    
    init() {
        self.modelContainer = PersistenceManager.shared.createContainer()
    }
    
    var body: some Scene {
        MainScene(modelContainer: modelContainer)
    }
}
