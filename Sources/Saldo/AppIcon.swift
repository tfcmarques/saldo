import AppKit

@MainActor
enum AppIcon {
    // Inside the .app the system already resolves the icon; plain `swift run` has to load the file.
    static let image: NSImage? = {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return NSApplication.shared.applicationIconImage
        }
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}
