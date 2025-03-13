import Cocoa
import AVKit

class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var wallpaperWindow: WallpaperWindow?
    private var settingsWindow: SettingsWindow?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Ensure app is activated as a menu bar app
        NSApp.setActivationPolicy(.accessory)
        
        // Configure status item
        if let button = statusItem.button {
            button.title = "🎬"
            button.target = self
        }
        
        // Create menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        
        // Listen for video path changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVideoPathChange),
            name: .init("VideoPathChanged"),
            object: nil
        )
        
        // Start video if auto-start is enabled
        if UserDefaults.standard.bool(forKey: "autoStart"),
           let savedPath = UserDefaults.standard.string(forKey: "videoPath") {
            startLiveWallpaper(path: savedPath)
        }
    }
    
    @objc func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func handleVideoPathChange(_ notification: Notification) {
        if let videoPath = notification.object as? String {
            startLiveWallpaper(path: videoPath)
        }
    }
    
    func startLiveWallpaper(path: String) {
        // Stop existing wallpaper if any
        wallpaperWindow?.close()
        
        // Create and show the wallpaper window
        wallpaperWindow = WallpaperWindow(videoPath: path)
        wallpaperWindow?.show()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        wallpaperWindow?.close()
        wallpaperWindow = nil
    }
}