import Foundation
import FirebaseCore
import FirebaseFirestore

/// Configures the default FirebaseApp + Firestore to point at the
/// emulator running on the Mac (reachable via Tailscale IP). No real
/// Firebase project, no GoogleService-Info.plist — matches the test
/// fixture's setup. Safe to call multiple times; first call wins.
@MainActor
func configureFirebaseForEmulator() {
    guard FirebaseApp.app() == nil else { return }

    let options = FirebaseOptions(googleAppID: "1:1:ios:1", gcmSenderID: "1")
    options.projectID = "demo-voices"
    options.apiKey = "fake-api-key"
    options.storageBucket = "demo-voices.appspot.com"
    FirebaseApp.configure(options: options)

    let firestore = Firestore.firestore()
    let settings = firestore.settings
    settings.host = "100.73.64.63:8080"
    settings.isSSLEnabled = false
    settings.cacheSettings = MemoryCacheSettings()
    firestore.settings = settings
}
