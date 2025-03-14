//
//  LiveWallpaperApp.swift
//  Created by Octexa
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
           let sources = IOPSCopyPowerSourcesList(powerSource)?.takeRetainedValue() as? [CFTypeRef] {
            
            for source in sources {
                if let description = IOPSGetPowerSourceDescription(powerSource, source)?.takeUnretainedValue() as? [String: Any] {
                    let isCharging = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
                    let batteryLevel = Double(description[kIOPSCurrentCapacityKey] as? Int ?? 100)
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

// MARK: - ColorSamplingManager
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

// MARK: - PreviewPlayerManager
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
                
                // Create NSImage
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 280, height: 158))
                
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

// MARK: - MenuBarController (for other logic, if needed)
class MenuBarController: ObservableObject {
    // We won’t actually create an NSMenu here, but we can keep the class 
    // for referencing in WallpaperWindowManager or if you want 
    // other logic. 
    //
    // If you truly don't need it, you can remove it. 
    // But let's keep it to avoid "Cannot find 'MenuBarController' in scope" errors.
    
    func updateIcon(isActive: Bool, color: NSColor? = nil) {
        // No-op or implement your custom logic if needed
    }
}

// MARK: - WallpaperWindowManager
class WallpaperWindowManager: ObservableObject {
    private var window: NSWindow?
    private var playerView: AVPlayerView?
    private var player: AVPlayer?
    private var menuBarController: MenuBarController
    private let colorSamplingManager = ColorSamplingManager.shared
    private let batteryMonitor = BatteryMonitor.shared
    private var wasPlayingBeforeLostFocus = false
    
    @Published var isPlaying: Bool = false
    
    init(menuBarController: MenuBarController) {
        self.menuBarController = menuBarController
        // If you have logic to create a wallpaper window, you can keep it. 
        // Otherwise, remove or adapt it. 
    }
    
    func start() {
        // Start the wallpaper logic
        isPlaying = true
    }
    
    func stop() {
        // Stop the wallpaper logic
        isPlaying = false
    }
    
    func togglePlayback() {
        if isPlaying {
            stop()
        } else {
            start()
        }
    }
}

// MARK: - ContentView
struct ContentView: View {
    // For demonstration, we include references to 
    // ModelManager, PreviewPlayerManager, and WallpaperWindowManager
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var modelManager = ModelManager.shared
    @StateObject private var previewManager = PreviewPlayerManager()
    @StateObject private var windowManager: WallpaperWindowManager
    
    init(windowManager: WallpaperWindowManager) {
        _windowManager = StateObject(wrappedValue: windowManager)
    }
    
    var body: some View {
        VStack {
            Text("Live Wallpaper Settings")
                .font(.headline)
                .padding(.top)
            
            // Example toggle
            Toggle("Auto-Start", isOn: Binding(
                get: { modelManager.settings?.autoStart ?? false },
                set: { newVal in
                    modelManager.settings?.autoStart = newVal
                    modelManager.updateSettings()
                }
            ))
            .padding()
            
            Button(windowManager.isPlaying ? "Stop Wallpaper" : "Start Wallpaper") {
                windowManager.togglePlayback()
            }
            .padding()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .padding()
        }
        .frame(width: 320, height: 220)
        .onAppear {
            modelManager.initialize(with: modelContext)
        }
    }
}

// MARK: - PopoverController
class PopoverController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    
    // Create an instance of our manager classes
    private let menuBarController = MenuBarController()
    private let windowManager: WallpaperWindowManager
    
    override init() {
        self.windowManager = WallpaperWindowManager(menuBarController: menuBarController)
        super.init()
        
        // 1) Create the status item (the menu bar icon).
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // 2) Assign an icon to the status item button
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "photo.fill", accessibilityDescription: "Wallpaper")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        // 3) Create the NSPopover
        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        
        // 4) Embed SwiftUI ContentView in the popover
        let contentView = ContentView(windowManager: windowManager)
            .modelContainer(PersistenceManager.shared.createContainer())
        
        popover.contentSize = NSSize(width: 320, height: 220)
        let viewController = NSViewController()
        viewController.view = NSHostingView(rootView: contentView)
        popover.contentViewController = viewController
    }
    
    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        true
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    private var popoverController: PopoverController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the popover controller so it sets up the menu bar icon
        popoverController = PopoverController()
    }
}

// MARK: - Main App
@main
struct LiveWallpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // We don't create a WindowGroup here.
        // The entire UI is in the popover, so no main window is needed.
        Settings {
            // Optionally empty
            EmptyView()
        }
    }
}
