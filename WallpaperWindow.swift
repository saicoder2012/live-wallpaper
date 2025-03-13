import Cocoa
import AVKit

class WallpaperWindow: NSWindow {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerLooper: AVPlayerLooper?
    
    init(videoPath: String) {
        // Create a borderless window that spans the main screen
        super.init(contentRect: NSScreen.main?.frame ?? .zero,
                  styleMask: [.borderless],
                  backing: .buffered,
                  defer: false)
        
        // Basic window setup
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(CGWindowLevelKey.desktopWindow)))
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        setupPlayer(with: videoPath)
    }
    
    private func setupPlayer(with path: String) {
        // Create an asset with limited options for memory efficiency
        let asset = AVAsset(url: URL(fileURLWithPath: path))
        let playerItem = AVPlayerItem(asset: asset)
        
        // Create player and optimize for memory
        player = AVPlayer(playerItem: playerItem)
        player?.automaticallyWaitsToMinimizeStalling = false
        
        // Create and configure player layer
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.frame = self.contentView?.bounds ?? .zero
        playerLayer?.videoGravity = .resizeAspect
        playerLayer?.drawsAsynchronously = true
        
        // Add player layer to window
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.addSublayer(playerLayer!)
        
        // Setup efficient looping
        playerLooper = AVPlayerLooper(player: player!, templateItem: playerItem)
        
        // Optimize playback
        player?.play()
    }
    
    func show() {
        self.makeKeyAndOrderFront(nil)
        
        // Ensure window stays in the right position
        if let screen = NSScreen.main {
            self.setFrame(screen.frame, display: true)
        }
    }
    
    deinit {
        playerLooper?.disableLooping()
        playerLooper = nil
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
    }
} 
