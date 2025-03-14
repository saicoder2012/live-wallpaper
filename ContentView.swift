//
//  LiveWallpaperApp.swift
//
//  Created on 13/01/25 By Octexa
//

import SwiftUI
import AppKit
import AVKit
import SwiftData
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
    
    init(lastUsedPath: String? = nil,
         autoStart: Bool = false,
         playbackMode: PlaybackMode = .loop,
         adaptiveMenuBar: Bool = true,
         thumbnailData: Data? = nil,
         batteryLimitEnabled: Bool = false,
         batteryLimitPercentage: Double = 20) {
        
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
           let sourcesCF = IOPSCopyPowerSourcesList(powerSource)?.takeRetainedValue() as? [CFTypeRef] {
            
            for source in sourcesCF {
                if let descriptionCF = IOPSGetPowerSourceDescription(powerSource, source)?.takeUnretainedValue() as? [String: Any] {
                    let isCharging = descriptionCF[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
                    let batteryLevel = Double(descriptionCF[kIOPSCurrentCapacityKey] as? Int ?? 100)
                    let percentage = batteryLevel
                    
                    DispatchQueue.main.async {
                        self.onBatteryLevelChanged?(percentage, isCharging)
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
    @Published var isVisible = true
    private var windowManager: WallpaperWindowManager?
    private var window: NSWindow?
    
    init() {
        setupStatusItem()
        setupMenu()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "photo.fill", accessibilityDescription: "Wallpaper")
            button.image?.isTemplate = true
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // Open Settings item
        let settingsItem = NSMenuItem(title: "Open Settings", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Toggle Wallpaper item
        let toggleItem = NSMenuItem(title: "Start Wallpaper", action: #selector(togglePlayback), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit item
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    func updateMenuPlaybackState(isPlaying: Bool) {
        if let menu = statusItem?.menu,
           let toggleItem = menu.items.first(where: { $0.action == #selector(togglePlayback) }) {
            toggleItem.title = isPlaying ? "Stop Wallpaper" : "Start Wallpaper"
        }
    }
    
    func setWindowManager(_ manager: WallpaperWindowManager) {
        self.windowManager = manager
    }
    
    func setWindow(_ window: NSWindow) {
        self.window = window
        print("Settings window set: \(window)")
    }
    
    @objc private func openSettings() {
        if let window = window {
            print("Settings window exists, attempting to open...")
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            print("No settings window found")
        }
    }
    
    @objc private func togglePlayback() {
        windowManager?.togglePlayback()
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func updateIcon(isActive: Bool, color: NSColor? = nil) {
        if let button = statusItem?.button {
            if let color = color {
                button.contentTintColor = color
            } else {
                button.contentTintColor = nil
            }
        }
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
    private var wasPlayingBeforeLostFocus = false
    
    @Published var isPlaying: Bool = false {
        didSet {
            menuBarController.updateMenuPlaybackState(isPlaying: isPlaying)
        }
    }
    
    init(menuBarController: MenuBarController) {
        self.menuBarController = menuBarController
        setupWindow()
        setupWorkspaceNotifications()
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
    
    private func setupWorkspaceNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleActiveAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
    
    @objc private func handleActiveAppChanged(_ notification: Notification) {
        if wasPlayingBeforeLostFocus {
            resumePlayback()
            wasPlayingBeforeLostFocus = false
        }
    }
    
    private func startColorSampling() {
        guard let currentItem = player?.currentItem,
              ModelManager.shared.settings?.adaptiveMenuBar == true else {
            return
        }
        
        let imageGenerator = AVAssetImageGenerator(asset: currentItem.asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        Task {
            do {
                // The new async call returns a tuple: (image: CGImage, actualTime: CMTime)
                let (cgImage, _) = try await imageGenerator.image(at: CMTime(seconds: 0, preferredTimescale: 600))
                
                // Convert CGImage to NSImage
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 100, height: 100))
                let dominantColor = ColorSamplingManager.shared.getDominantColor(from: nsImage)
                
                await MainActor.run {
                    self.menuBarController.updateIcon(isActive: true, color: dominantColor)
                }
            } catch {
                print("Error generating thumbnail for color sampling: \(error)")
                await MainActor.run {
                    self.menuBarController.updateIcon(isActive: true)
                }
            }
        }
    }
    
    private func stopColorSampling() {
        menuBarController.updateIcon(isActive: false)
    }
    
    func setVideo(url: URL) {
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        
        // Safely configure audio settings
        configureAudioSettings(for: playerItem, with: asset)
        setupPlayer(with: playerItem)
    }
    
    private func configureAudioSettings(for playerItem: AVPlayerItem, with asset: AVAsset) {
        Task {
            do {
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                // Make sure we have at least one track
                guard let audioTrack = audioTracks.first else {
                    print("No audio track found; skipping audio mix setup.")
                    return
                }
                
                await MainActor.run {
                    let audioMix = AVMutableAudioMix()
                    let audioInputParameters = AVMutableAudioMixInputParameters(track: audioTrack)
                    audioInputParameters.setVolume(0, at: .zero)
                    audioMix.inputParameters = [audioInputParameters]
                    playerItem.audioMix = audioMix
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
    
    private func pausePlayback() {
        player?.pause()
    }
    
    private func resumePlayback() {
        player?.play()
        wasPlayingBeforeLostFocus = false
    }
    
    func start() {
        window?.orderFront(nil)
        player?.play()
        isPlaying = true
        startColorSampling()
    }
    
    func stop() {
        wasPlayingBeforeLostFocus = false
        player?.pause()
        window?.orderOut(nil)
        isPlaying = false
        stopColorSampling()
    }
    
    func cleanup() {
        stopColorSampling()
        player?.pause()
        player = nil
        window?.close()
        window = nil
    }
    
    func togglePlayback() {
        if isPlaying {
            stop()
        } else if let path = ModelManager.shared.settings?.lastUsedPath,
                  let url = URL(string: path) {
            setVideo(url: url)
            start()
        }
    }
}

// MARK: - Preview Player Manager
class PreviewPlayerManager: ObservableObject {
    @MainActor @Published private(set) var previewImage: NSImage?
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    
    @MainActor
    func setupPreview(url: URL, completion: ((Data?) -> Void)? = nil) {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        Task {
            do {
                // The new async call returns a tuple: (image: CGImage, actualTime: CMTime)
                let (cgImage, _) = try await imageGenerator.image(at: CMTime(seconds: 0, preferredTimescale: 600))
                
                // Create NSImage directly
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 280, height: 158))
                
                // Update preview
                await MainActor.run {
                    self.previewImage = nsImage
                    if let tiffData = nsImage.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData),
                       let thumbnailData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                        completion?(thumbnailData)
                    } else {
                        completion?(nil)
                    }
                }
            } catch {
                print("Could not generate thumbnail: \(error)")
                await MainActor.run {
                    self.previewImage = nil
                    completion?(nil)
                }
            }
        }
        
        cleanup()
    }
    
    @MainActor
    func setPreviewFromData(_ data: Data?) {
        guard let data = data else {
            previewImage = nil
            return
        }
        
        if let nsImage = NSImage(data: data) {
            previewImage = nsImage
        }
    }
    
    func cleanup() {
        Task { @MainActor in
            player?.pause()
            player = nil
            playerLayer = nil
            videoOutput = nil
        }
    }
}

// MARK: - Custom Button Styles
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.controlActiveState) private var controlActiveState
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundColor(.white)
            .cornerRadius(8)
            .opacity(controlActiveState == .inactive ? 0.5 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Content View
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var windowManager: WallpaperWindowManager
    @ObservedObject private var modelManager = ModelManager.shared
    @StateObject private var previewManager = PreviewPlayerManager()
    @Environment(\.colorScheme) private var colorScheme
    
    init(menuBarController: MenuBarController) {
        _windowManager = StateObject(wrappedValue: WallpaperWindowManager(menuBarController: menuBarController))
        menuBarController.setWindowManager(windowManager)
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                    Text("Live Wallpaper")
                        .font(.system(size: 20, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Preview Card
                        VStack(spacing: 0) {
                            if let previewImage = previewManager.previewImage {
                                Image(nsImage: previewImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 160)
                                    .clipped()
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.1))
                                    
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(.gray)
                                        Text("No wallpaper selected")
                                            .font(.system(size: 13))
                                            .foregroundColor(.gray)
                                    }
                                }
                                .frame(height: 160)
                            }
                            
                            // Control buttons
                            HStack(spacing: 16) {
                                Button(action: chooseVideo) {
                                    HStack {
                                        Image(systemName: "plus")
                                        Text("Choose")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(ModernButtonStyle(type: .secondary))
                                
                                Button(action: togglePlayback) {
                                    HStack {
                                        Image(systemName: windowManager.isPlaying ? "stop.fill" : "play.fill")
                                        Text(windowManager.isPlaying ? "Stop" : "Start")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(ModernButtonStyle(type: .primary))
                            }
                            .padding(12)
                        }
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                        
                        // Settings Section
                        VStack(spacing: 16) {
                            Text("Settings")
                                .font(.system(size: 15, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            VStack(spacing: 4) {
                                ModernToggleRow("Auto-start on launch",
                                                systemImage: "clock",
                                                isOn: Binding(
                                                    get: { modelManager.settings?.autoStart ?? false },
                                                    set: { updateAutoStart($0) }
                                                ))
                                
                                Divider()
                                
                                ModernToggleRow("Adaptive menu bar",
                                                systemImage: "paintpalette",
                                                isOn: Binding(
                                                    get: { modelManager.settings?.adaptiveMenuBar ?? true },
                                                    set: { updateAdaptiveMenuBar($0) }
                                                ))
                                
                                Divider()
                                
                                ModernToggleRow("Battery limit",
                                                systemImage: "battery.75",
                                                isOn: Binding(
                                                    get: { modelManager.settings?.batteryLimitEnabled ?? false },
                                                    set: { updateBatteryLimit($0) }
                                                ))
                                
                                if modelManager.settings?.batteryLimitEnabled == true {
                                    VStack(spacing: 8) {
                                        Divider()
                                        HStack {
                                            Image(systemName: "bolt.circle")
                                                .foregroundStyle(.orange)
                                            Slider(value: Binding(
                                                get: { modelManager.settings?.batteryLimitPercentage ?? 20 },
                                                set: { updateBatteryLimitPercentage($0) }
                                            ), in: 10...80, step: 5)
                                            Text("\(Int(modelManager.settings?.batteryLimitPercentage ?? 20))%")
                                                .monospacedDigit()
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        Button("Quit Application") {
                            NSApplication.shared.terminate(nil)
                        }
                        .buttonStyle(ModernButtonStyle(type: .destructive))
                    }
                    .padding()
                }
            }
        }
        .frame(width: 320, height: 480)
        .onAppear {
            modelManager.initialize(with: modelContext)
            handleOnAppear()
        }
    }
    
    private func handleOnAppear() {
        previewManager.setPreviewFromData(modelManager.settings?.thumbnailData)
        loadSavedVideo()
    }
    
    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // Save the file URL as a bookmark for persistent access
                do {
                    let bookmarkData = try url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    
                    // Store both the path and bookmark data
                    modelManager.settings?.lastUsedPath = url.absoluteString
                    UserDefaults.standard.set(bookmarkData, forKey: "videoBookmark")
                    
                    // Update preview and start playback
                    previewManager.setupPreview(url: url) { thumbnailData in
                        modelManager.settings?.thumbnailData = thumbnailData
                        modelManager.updateSettings()
                    }
                    windowManager.setVideo(url: url)
                    windowManager.start()
                } catch {
                    print("Failed to create bookmark: \(error)")
                }
            }
        }
    }
    
    private func loadSavedVideo() {
        if let path = modelManager.settings?.lastUsedPath,
           let url = URL(string: path),
           let bookmarkData = UserDefaults.standard.data(forKey: "videoBookmark") {
            
            do {
                var isStale = false
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                // Start accessing the security-scoped resource
                guard resolvedURL.startAccessingSecurityScopedResource() else {
                    print("Failed to access the video file")
                    return
                }
                
                // Update the UI and start playback if autoStart is enabled
                previewManager.setPreviewFromData(modelManager.settings?.thumbnailData)
                windowManager.setVideo(url: resolvedURL)
                
                if modelManager.settings?.autoStart == true {
                    windowManager.start()
                }
                
                // Stop accessing the security-scoped resource when done
                resolvedURL.stopAccessingSecurityScopedResource()
            } catch {
                print("Failed to resolve bookmark: \(error)")
            }
        }
    }
    
    private func togglePlayback() {
        if windowManager.isPlaying {
            windowManager.stop()
        } else if let path = modelManager.settings?.lastUsedPath,
                  let url = URL(string: path) {
            windowManager.setVideo(url: url)
            windowManager.start()
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
    let modelContainer: ModelContainer
    
    var body: some Scene {
        WindowGroup {
            ContentView(menuBarController: menuBarController)
                .modelContainer(modelContainer)
                .frame(width: 320, height: 480)
                .background(VisualEffectView())
                .onAppear {
                    setupWindow()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
    
    private func setupWindow() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                print("Main window initialized: \(window)")
                // Configure window behavior
                window.standardWindowButton(.closeButton)?.target = window
                window.standardWindowButton(.closeButton)?.action = #selector(NSWindow.miniaturize(_:))
                
                // Store window reference in MenuBarController
                menuBarController.setWindow(window)
                
                // Hide window on launch
                window.miniaturize(nil)
            } else {
                print("Main window is nil")
            }
        }
    }
}

// Add this new ViewRepresentable for the window background
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .windowBackground
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - App Entry Point
@main
struct LiveWallpaperApp: App {
    let modelContainer: ModelContainer
    
    init() {
        self.modelContainer = PersistenceManager.shared.createContainer()
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    
    var body: some Scene {
        MainScene(modelContainer: modelContainer)
    }
}

// Modern Button Types and Styles
enum ModernButtonType {
    case primary, secondary, destructive
    
    var backgroundColor: Color {
        switch self {
        case .primary: return .blue
        case .secondary: return .gray.opacity(0.15)
        case .destructive: return .red.opacity(0.15)
        }
    }
    
    var foregroundColor: Color {
        switch self {
        case .primary: return .white
        case .secondary: return .primary
        case .destructive: return .red
        }
    }
}

struct ModernButtonStyle: ButtonStyle {
    let type: ModernButtonType
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(type.backgroundColor.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundColor(type.foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ModernToggleRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    
    init(_ title: String, systemImage: String, isOn: Binding<Bool>) {
        self.title = title
        self.systemImage = systemImage
        self._isOn = isOn
    }
    
    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
            Text(title)
                .font(.system(size: 13))
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
