import Foundation

// Deploy-relevant identifiers, resolved at runtime from the build
// configuration (Config/Base.xcconfig + git-ignored Local.xcconfig) so the
// public repository keeps its placeholders while private builds carry real
// ids. Compiled into the app, the Share Extension and the Widgets — but only
// `bundleID` and `appGroup` are backed by every target's Info.plist; the
// remaining properties are app-only and fall back to placeholders elsewhere.
enum AppIdentifiers {

    // Placeholders shipped in the public repo (mirroring Config/Base.xcconfig);
    // only used when a value is missing from the bundle, which a configured
    // build never hits.
    private static let placeholderBundleID = "com.example.brain-ios"
    static let placeholderGoogleClientID = "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com"

    // Bundle id of the running target (app or extension).
    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? placeholderBundleID
    }

    // App Group shared by app, Share Extension and Widgets. Every target's
    // Info.plist carries BrainAppGroupID = $(BRAIN_APP_GROUP).
    static var appGroup: String {
        infoValue("BrainAppGroupID") ?? "group.\(placeholderBundleID)"
    }

    // CloudKit container (main app; Info.plist BrainICloudContainerID).
    static var iCloudContainer: String {
        infoValue("BrainICloudContainerID") ?? "iCloud.\(placeholderBundleID)"
    }

    // Google OAuth iOS client id (main app; Info.plist BrainGoogleClientID).
    static var googleClientID: String {
        infoValue("BrainGoogleClientID") ?? placeholderGoogleClientID
    }

    // BGTaskScheduler identifiers. They must match
    // BGTaskSchedulerPermittedIdentifiers in the app's Info.plist, which
    // derives them from PRODUCT_BUNDLE_IDENTIFIER the same way.
    enum BackgroundTask {
        static var analysis: String { bundleID + ".analysis" }
        static var deepAnalysis: String { bundleID + ".deep-analysis" }
        static var mailSync: String { bundleID + ".mail-sync" }
    }

    // CoreSpotlight domain for indexed entries.
    static var spotlightDomain: String { bundleID + ".entries" }

    // StoreKit product id of the one-time purchase; the product in App Store
    // Connect must follow the same "<bundle id>.lifetime" convention.
    static var storeKitLifetimeProduct: String { bundleID + ".lifetime" }

    // Reads a substituted Info.plist value; an unexpanded "$(...)" (build
    // setting not resolved) counts as missing so callers get the fallback.
    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.hasPrefix("$(") else {
            return nil
        }
        return value
    }
}
