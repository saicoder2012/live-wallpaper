import SwiftUI
import AppKit
import AVFoundation
import SwiftData
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

// MARK: - Battery Monitor (same as before)
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

// MARK: - Persistence Manager (same as before)
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

// MARK: - ModelManager, ColorSamplingManager, etc. (same as before)
//  ... (Keep your existing classes and logic: ModelManager, ColorSamplingManager, 
//       WallpaperWindowManager, etc. You just won't be using a separate NSWindow 
//       for the settings UI. We'll embed ContentView in a popover.)

// For brevity, assume the rest of your classes remain the same. 
// The only difference is how we present the ContentView in a popover instead 
// of a separate window. 
//
// The code below focuses on how to create a status item + popover. 
// If you rely on a window for the wallpaper, keep that logic in 
// WallpaperWindowManager. But the *settings UI* is now a popover.

// MARK: - ContentView
struct ContentView: View {
    // All your existing logic from your "ContentView" can remain
    // exactly as is. The only difference is that it's displayed
    // in a popover rather than in a window.
    
    // For example:
    @Environment(\.modelContext) private var modelContext
    @StateObject private var windowManager: WallpaperWindowManager
    @ObservedObject private var modelManager = ModelManager.shared
    @StateObject private var previewManager = PreviewPlayerManager()
    
    init(windowManager: WallpaperWindowManager) {
        _windowManager = StateObject(wrappedValue: windowManager)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Live Wallpaper Settings")
                .font(.title3)
                .padding()
            
            // ... Your existing UI ...
            // For example, a button to choose video, toggles, etc.
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.top, 10)
        }
        .frame(width: 320, height: 480)
        .onAppear {
            modelManager.initialize(with: modelContext)
            // ...
        }
    }
}

// MARK: - PopoverController
/// Manages an NSPopover that displays our SwiftUI ContentView.
class PopoverController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let windowManager = WallpaperWindowManager(menuBarController: MenuBarController())
    
    override init() {
        super.init()
        
        // 1) Create the status item (the menu bar icon).
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // 2) Assign an icon to the status item button
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "photo.fill", accessibilityDescription: "Wallpaper")
            button.image?.isTemplate = true
            
            // 3) Set the button's action to toggle the popover
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        // 4) Create the NSPopover and embed ContentView
        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        
        // Embed the SwiftUI ContentView in the popover
        let contentView = ContentView(windowManager: windowManager)
            .modelContainer(PersistenceManager.shared.createContainer())
        
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = NSHostingView(rootView: contentView)
    }
    
    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Show the popover, anchored to the status item button
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    // Optional: Close the popover if user clicks outside
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        true
    }
}

// MARK: - App Entry Point
@main
struct LiveWallpaperApp: App {
    // We don't create a WindowGroup here. Instead, we set up
    // our popover in the initializer (or somewhere) so that
    // there's no main app window, just a menu bar item.
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // We can have an empty scene or no scenes at all.
        // If you want zero Dock icons, also set the LSUIElement 
        // or "Application is agent" property in Info.plist.
        Settings {
            // Optionally empty
            EmptyView()
        }
    }
}

// MARK: - AppDelegate
/// We use an NSApplicationDelegate to set up the popover on launch.
class AppDelegate: NSObject, NSApplicationDelegate {
    private var popoverController: PopoverController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the popover controller so it sets up the menu bar icon
        popoverController = PopoverController()
    }
}
