import SwiftUI

/// The app's entry point. Debug builds can be asked to draw screenshots and quit before anything
/// else happens (see `LicenseShots`); otherwise, and always in release builds, it's just the app.
@main
enum SeawallMain {
    @MainActor
    static func main() {
        #if DEBUG
        LicenseShots.runIfAsked()
        #endif
        SeawallApp.main()
    }
}
