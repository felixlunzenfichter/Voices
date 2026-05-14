import Foundation
import FirebaseCore
import FirebaseFirestore
@testable import Voices

/// Configures FirebaseApp + Firestore to point at the local emulator
/// (no real Firebase project, no GoogleService-Info.plist).
/// `fresh()` wipes the emulator's documents so tests start clean.
@MainActor
enum FirebaseFixture {
    static let projectID = "demo-voices"
    static let host = "100.73.64.63:8080"
    /// Tests that need writer/reader instances to see each other's
    /// listened-marks share this viewer ID.
    static let sharedViewer = UUID()

    static func fresh() async throws {
        configureDefaultAppIfNeeded()
        try await drainPendingWrites()
        try await clearEmulator()
    }

    /// Wait until every Firestore client we've previously vended has
    /// flushed its in-flight writes to the emulator. Without this, a
    /// prior test's optimistic write can land on the server *after*
    /// `clearEmulator()` runs and contaminate the next test.
    private static func drainPendingWrites() async throws {
        if configuredDefaultApp {
            try await Firestore.firestore().waitForPendingWrites()
        }
        for firestore in namedFirestores.values {
            try await firestore.waitForPendingWrites()
        }
    }

    /// Vends an isolated FirebaseDatabase backed by a named FirebaseApp.
    /// Two instances with different `appName` have independent Firestore
    /// clients and independent caches — cross-instance propagation must
    /// go through the backend. Defaults to the shared viewer so that
    /// writer/reader pairs observe each other's listened marks.
    static func makeDatabase(appName: String, viewer: UUID = sharedViewer) -> FirebaseDatabase {
        let firestore = firestoreForNamedApp(appName)
        return FirebaseDatabase(firestore: firestore, viewer: viewer)
    }

    private static var configuredDefaultApp = false
    private static var namedFirestores: [String: Firestore] = [:]

    private static func configureDefaultAppIfNeeded() {
        guard !configuredDefaultApp else { return }
        configuredDefaultApp = true
        // The host app's VoicesApp.init may have already configured the
        // default FirebaseApp + Firestore settings against the same
        // emulator. If so, leave it alone — re-setting Firestore
        // settings after first use is a fatal error.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure(options: makeOptions())
            applyEmulatorSettings(to: Firestore.firestore())
        }
    }

    private static func firestoreForNamedApp(_ name: String) -> Firestore {
        if let firestore = namedFirestores[name] { return firestore }
        FirebaseApp.configure(name: name, options: makeOptions())
        let app = FirebaseApp.app(name: name)!
        let firestore = Firestore.firestore(app: app)
        applyEmulatorSettings(to: firestore)
        namedFirestores[name] = firestore
        return firestore
    }

    private static func makeOptions() -> FirebaseOptions {
        let options = FirebaseOptions(googleAppID: "1:1:ios:1", gcmSenderID: "1")
        options.projectID = projectID
        options.apiKey = "fake-api-key"
        options.storageBucket = "\(projectID).appspot.com"
        return options
    }

    private static func applyEmulatorSettings(to firestore: Firestore) {
        let settings = firestore.settings
        settings.host = host
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        firestore.settings = settings
    }

    private static func clearEmulator() async throws {
        let path = "/emulator/v1/projects/\(projectID)/databases/%28default%29/documents"
        let url = URL(string: "http://\(host)\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (_, response) = try await URLSession(configuration: .ephemeral).data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "FirebaseFixture",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: "emulator clear failed at \(url.absoluteString)"]
            )
        }
    }
}
