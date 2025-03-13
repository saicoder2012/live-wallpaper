import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var isShowingFilePicker = false
    @State private var currentVideoPath: String? = UserDefaults.standard.string(forKey: "videoPath")
    @State private var isAutoStartEnabled = UserDefaults.standard.bool(forKey: "autoStart")
    @Environment(\.openURL) private var openURL
    
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
            
            Button(action: { isShowingFilePicker = true }) {
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
                Button(action: {
                    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                        appDelegate.startLiveWallpaper(path: currentVideoPath!)
                    }
                }) {
                    Label("Apply Wallpaper", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            
            Divider()
            
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding()
        .frame(width: 300)
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.movie, .video],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    currentVideoPath = url.path
                    UserDefaults.standard.set(url.path, forKey: "videoPath")
                    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                        appDelegate.startLiveWallpaper(path: url.path)
                    }
                }
            case .failure(let error):
                print("Error selecting file: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupLoginItem(enabled: Bool) {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        
        if enabled {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            configuration.hidesOthers = false
            
            NSWorkspace.shared.openApplication(
                at: Bundle.main.bundleURL,
                configuration: configuration
            ) { _, error in
                if let error = error {
                    print("Error setting up login item: \(error)")
                }
            }
        } else {
            // Remove login item
            // This is handled by the system when toggling off
        }
    }
}
