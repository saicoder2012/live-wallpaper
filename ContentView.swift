import SwiftUI
import AVFoundation
import AppKit

struct ContentView: View {
    @State private var isShowingFilePicker = false
    @State private var currentVideoPath: String? = UserDefaults.standard.string(forKey: "videoPath")
    @State private var isAutoStartEnabled = UserDefaults.standard.bool(forKey: "autoStart")
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Live Wallpaper")
                .font(.headline)
            
            if let path = currentVideoPath {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Video:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            
            Button {
                selectVideoFile()
            } label: {
                Label(
                    currentVideoPath == nil ? "Select Video" : "Change Video",
                    systemImage: "video.badge.plus"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            Toggle("Start on Login", isOn: $isAutoStartEnabled)
                .onChange(of: isAutoStartEnabled) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "autoStart")
                    setupLoginItem(enabled: newValue)
                }
            
            if currentVideoPath != nil {
                Button {
                    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                        appDelegate.startLiveWallpaper(path: currentVideoPath!)
                    }
                } label: {
                    Label("Apply Wallpaper", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            
            Divider()
            
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding()
        .frame(width: 300)
    }
    
    // File Picker functionality
    func selectVideoFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["mp4", "mov", "m4v", "mpg", "mpeg"]
        
        panel.begin { result in
            if result == .OK, let url = panel.url {
                self.currentVideoPath = url.path
                UserDefaults.standard.set(url.path, forKey: "videoPath")
                
                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                    appDelegate.startLiveWallpaper(path: url.path)
                }
            }
        }
    }
    
    private func setupLoginItem(enabled: Bool) {
        if enabled {
            // Add login item
            let bundlePath = Bundle.main.bundlePath
            let scriptContent = "tell application \"System Events\" to make login item at end with properties {path:\"\(bundlePath)\", hidden:false}"
            
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", scriptContent]
            
            do {
                try task.run()
            } catch {
                print("Error setting up login item: \(error)")
            }
        } else {
            // Remove login item
            let bundleName = (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "Live Wallpaper"
            let scriptContent = "tell application \"System Events\" to delete (every login item whose name is \"\(bundleName)\")"
            
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", scriptContent]
            
            do {
                try task.run()
            } catch {
                print("Error removing login item: \(error)")
            }
        }
    }
}

// PreviewProvider for Xcode canvas
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
