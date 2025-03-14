import SwiftUI
import AppKit

/// The main entry point for your SwiftUI app.
@main
struct LiveWallpaperApp: App {
    // We manage the status item & popover via an NSApplicationDelegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No main window, just a hidden Settings scene (optional).
        Settings {
            EmptyView()
        }
    }
}

/// The AppDelegate sets up the popover controller on launch.
class AppDelegate: NSObject, NSApplicationDelegate {
    private var popoverController: PopoverController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the popover controller, which creates the menu bar icon.
        popoverController = PopoverController()
    }
}

/// A controller that handles the menu bar icon and popover logic.
class PopoverController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    
    override init() {
        super.init()
        
        // 1) Create the status bar item (the menu bar icon).
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // 2) Configure the icon
        if let button = statusItem.button {
            // Provide any SF Symbol or custom NSImage here
            button.image = NSImage(systemSymbolName: "photo.fill", accessibilityDescription: "Wallpaper")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        // 3) Create the NSPopover
        popover = NSPopover()
        popover.behavior = .transient // closes if user clicks outside
        popover.delegate = self
        
        // 4) Embed a minimal SwiftUI view in the popover
        let contentView = MinimalPopoverView()
        
        // 5) Put the SwiftUI view inside the popover's contentViewController
        let viewController = NSViewController()
        viewController.view = NSHostingView(rootView: contentView)
        popover.contentViewController = viewController
        
        // Optionally set a popover size:
        // popover.contentSize = NSSize(width: 200, height: 140)
    }
    
    /// Toggles the popover open/closed when the menu bar icon is clicked.
    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            // Bring the app to the foreground
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        // Return true to allow the popover to close when user clicks outside
        return true
    }
}

/// A minimal SwiftUI view that appears in the popover.
struct MinimalPopoverView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Live Wallpaper")
                .font(.headline)
            
            Button("Start") {
                // Insert your "start" logic here
                print("Start wallpaper pressed")
            }
            
            Button("Stop") {
                // Insert your "stop" logic here
                print("Stop wallpaper pressed")
            }
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        // Adjust the popover size here if desired:
        .frame(width: 200, height: 140)
    }
}
