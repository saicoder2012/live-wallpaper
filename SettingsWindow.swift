import Cocoa
import AVKit

class SettingsWindow: NSWindow {
    private var videoPathLabel: NSTextField!
    private var autoStartCheckbox: NSButton!
    private var previewView: NSView!
    private var player: AVPlayer?
    
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                  styleMask: [.titled, .closable, .miniaturizable],
                  backing: .buffered,
                  defer: false)
        
        self.title = "Live Wallpaper Settings"
        self.center()
        setupUI()
        loadSettings()
    }
    
    private func setupUI() {
        let contentView = NSView(frame: self.contentView!.bounds)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        // Video Preview Area
        previewView = NSView(frame: NSRect(x: 20, y: 140, width: 560, height: 240))
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = NSColor.black.cgColor
        previewView.layer?.cornerRadius = 8
        contentView.addSubview(previewView)
        
        // Current Video Path Label
        videoPathLabel = NSTextField(frame: NSRect(x: 20, y: 100, width: 440, height: 30))
        videoPathLabel.isEditable = false
        videoPathLabel.isBezeled = true
        videoPathLabel.drawsBackground = true
        videoPathLabel.stringValue = "No video selected"
        contentView.addSubview(videoPathLabel)
        
        // Select Video Button
        let selectButton = NSButton(frame: NSRect(x: 470, y: 100, width: 110, height: 30))
        selectButton.title = "Select Video"
        selectButton.bezelStyle = .rounded
        selectButton.target = self
        selectButton.action = #selector(selectVideo)
        contentView.addSubview(selectButton)
        
        // Auto Start Checkbox
        autoStartCheckbox = NSButton(frame: NSRect(x: 20, y: 60, width: 200, height: 30))
        autoStartCheckbox.title = "Start on Login"
        autoStartCheckbox.setButtonType(.switch)
        autoStartCheckbox.target = self
        autoStartCheckbox.action = #selector(toggleAutoStart)
        contentView.addSubview(autoStartCheckbox)
        
        // Apply Button
        let applyButton = NSButton(frame: NSRect(x: 470, y: 20, width: 110, height: 30))
        applyButton.title = "Apply"
        applyButton.bezelStyle = .rounded
        applyButton.target = self
        applyButton.action = #selector(applySettings)
        contentView.addSubview(applyButton)
        
        self.contentView = contentView
    }
    
    private func loadSettings() {
        if let videoPath = UserDefaults.standard.string(forKey: "videoPath") {
            videoPathLabel.stringValue = videoPath
            setupVideoPreview(path: videoPath)
        }
        
        let isAutoStart = UserDefaults.standard.bool(forKey: "autoStart")
        autoStartCheckbox.state = isAutoStart ? .on : .off
    }
    
    @objc private func selectVideo() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video]
        
        panel.beginSheetModal(for: self) { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.videoPathLabel.stringValue = url.path
                self?.setupVideoPreview(path: url.path)
            }
        }
    }
    
    private func setupVideoPreview(path: String) {
        // Remove existing player layer if any
        previewView.layer?.sublayers?.removeAll()
        
        let url = URL(fileURLWithPath: path)
        player = AVPlayer(url: url)
        
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = previewView.bounds
        playerLayer.videoGravity = .resizeAspect
        previewView.layer?.addSublayer(playerLayer)
        
        // Loop video
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                            object: player?.currentItem,
                                            queue: .main) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }
        
        player?.play()
    }
    
    @objc private func toggleAutoStart() {
        let isAutoStart = autoStartCheckbox.state == .on
        UserDefaults.standard.set(isAutoStart, forKey: "autoStart")
        
        if isAutoStart {
            setupAutoStart()
        } else {
            removeAutoStart()
        }
    }
    
    private func setupAutoStart() {
        // Get the app's bundle identifier
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", """
            tell application "System Events"
                make login item at end with properties {path:"/Applications/Live Wallpaper.app", hidden:false}
            end tell
            """]
        
        try? task.run()
    }
    
    private func removeAutoStart() {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", """
            tell application "System Events"
                delete login item "Live Wallpaper"
            end tell
            """]
        
        try? task.run()
    }
    
    @objc private func applySettings() {
        let videoPath = videoPathLabel.stringValue
        if FileManager.default.fileExists(atPath: videoPath) {
            UserDefaults.standard.set(videoPath, forKey: "videoPath")
            NotificationCenter.default.post(name: .init("VideoPathChanged"), object: videoPath)
        }
        
        self.close()
    }
    
    deinit {
        player?.pause()
        player = nil
    }
}