import Foundation
import CryptoKit
import os.log

// Certificate pinning for LLM API calls. (F-01: Real SPKI pinning, not a stub)
// Validates server certificates against known SHA-256 hashes of the Subject Public Key Info (SPKI).
// Each host has a leaf pin AND a backup pin (intermediate CA) per RFC 7469.
//
// H6: TOFU (Trust-on-First-Use) fallback for certificate rotation.
// When hardcoded pins don't match but TLS validates OK:
// - If TOFU is enabled (opt-in in Settings): accept and store new pin, log warning
// - If TOFU is disabled (default): reject connection (original behavior)
// @unchecked Sendable: Safe — singleton, session eagerly initialized in init(),
// no mutable state after construction. The lazy var is resolved before shared access.
final class PinnedURLSession: NSObject, URLSessionDelegate, @unchecked Sendable {

    static let shared = PinnedURLSession()

    private let logger = Logger(subsystem: "com.example.brain-ios", category: "CertificatePinning")

    // SPKI SHA-256 pin hashes per host.
    // Each host has at least 2 pins: leaf + intermediate CA (backup per RFC 7469).
    // Pins extracted 2026-03-19. Must be updated when certificates rotate.
    //
    // To extract a pin:
    //   echo | openssl s_client -connect HOST:443 -servername HOST -showcerts 2>/dev/null \
    //     | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der \
    //     | openssl dgst -sha256 -binary | base64
    private let pinHashes: [String: Set<String>] = [
        "api.anthropic.com": [
            "60QDDZy98CjK1XTBTlPbInyzJzi+817KvW+usCk6r+o=",  // leaf
            "kIdp6NNEd8wsugYyyIYFsi1ylMCED3hZbSR8ZFsa/A4=",  // intermediate CA (backup)
        ],
        "api.claude.ai": [
            "60QDDZy98CjK1XTBTlPbInyzJzi+817KvW+usCk6r+o=",  // same provider as api.anthropic.com
            "kIdp6NNEd8wsugYyyIYFsi1ylMCED3hZbSR8ZFsa/A4=",
        ],
        "api.openai.com": [
            "xiKNSl8SLMeEvynHDp4SxLxmkAJJf+66AglYicZnjgY=",  // leaf
            "kIdp6NNEd8wsugYyyIYFsi1ylMCED3hZbSR8ZFsa/A4=",  // intermediate CA (backup)
        ],
        "generativelanguage.googleapis.com": [               // (F-15: was missing)
            "bYvqDVqIMlWYWpupuwhVBE2NreKTNE0wxjmUfIFv3bA=",  // leaf
            "YPtHaftLw6/0vnc2BnNKGF54xiCA28WFcccjkA4ypCM=",  // intermediate CA (backup)
        ],
    ]

    private let pinnedHosts: Set<String>

    // H6: Keychain key for TOFU-learned pins per host (migrated from UserDefaults in A1)
    private static let tofuPinsKeychainKey = "certificatePinning.tofuPins"
    // H6: UserDefaults key for TOFU opt-in setting (not sensitive, stays in UserDefaults)
    static let tofuEnabledKey = "certificatePinning.tofuEnabled"
    // Legacy UserDefaults key for migration
    private static let tofuPinsLegacyKey = "certificatePinning.tofuPins"
    private let keychainService = KeychainService()

    // Initialized lazily because URLSession(delegate: self) requires super.init() first.
    // Thread-safe: PinnedURLSession.shared is created once; subsequent accesses are reads.
    private(set) lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        // LLM calls can take several minutes (long completions, tool use)
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    override init() {
        self.pinnedHosts = Set(pinHashes.keys)
        super.init()
        // Eagerly initialize session to avoid lazy data race
        _ = self.session
        // A1: Migrate TOFU pins from UserDefaults to Keychain (one-time)
        migrateTofuPinsToKeychain()
    }

    // A1: One-time migration of TOFU pins from UserDefaults to Keychain
    private func migrateTofuPinsToKeychain() {
        guard let legacy = UserDefaults.standard.dictionary(forKey: Self.tofuPinsLegacyKey) as? [String: [String]],
              !legacy.isEmpty else { return }
        // Serialize to JSON and store in Keychain
        if let jsonData = try? JSONSerialization.data(withJSONObject: legacy),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            try? keychainService.save(key: Self.tofuPinsKeychainKey, value: jsonString)
        }
        // Remove from UserDefaults
        UserDefaults.standard.removeObject(forKey: Self.tofuPinsLegacyKey)
        logger.info("Migrated TOFU pins from UserDefaults to Keychain")
    }

    // H6/A1: Load TOFU-learned pins from Keychain
    private func tofuPins(for host: String) -> Set<String> {
        guard let jsonString = keychainService.read(key: Self.tofuPinsKeychainKey),
              let jsonData = jsonString.data(using: .utf8),
              let allTofu = try? JSONSerialization.jsonObject(with: jsonData) as? [String: [String]]
        else { return [] }
        return Set(allTofu[host] ?? [])
    }

    // H6/A1: Save a TOFU-learned pin for a host in Keychain (max 5 per host, evict oldest)
    private func saveTofuPin(_ pin: String, for host: String) {
        var allTofu: [String: [String]] = [:]
        if let jsonString = keychainService.read(key: Self.tofuPinsKeychainKey),
           let jsonData = jsonString.data(using: .utf8),
           let existing = try? JSONSerialization.jsonObject(with: jsonData) as? [String: [String]] {
            allTofu = existing
        }
        var hostPins = allTofu[host] ?? []
        if !hostPins.contains(pin) {
            hostPins.append(pin)
            // Cap at 5 pins per host — evict oldest on overflow
            if hostPins.count > 5 {
                hostPins.removeFirst(hostPins.count - 5)
            }
            allTofu[host] = hostPins
            if let jsonData = try? JSONSerialization.data(withJSONObject: allTofu),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                try? keychainService.save(key: Self.tofuPinsKeychainKey, value: jsonString)
            }
        }
    }

    // H6: Check if TOFU is enabled (opt-in, default: false)
    private var isTofuEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.tofuEnabledKey)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              pinnedHosts.contains(challenge.protectionSpace.host)
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // Evaluate standard TLS first
        let policy = SecPolicyCreateSSL(true, host as CFString)
        SecTrustSetPolicies(serverTrust, policy)

        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            logger.error("TLS validation failed for \(host): \(error.debugDescription)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Pin validation: check if ANY certificate in the chain matches a known pin.
        // Note: Pins are SHA-256 hashes of the raw public key (SecKeyCopyExternalRepresentation),
        // NOT the full ASN.1 SPKI structure. This is consistent with how they were extracted
        // (openssl pkey -pubin -outform der | openssl dgst -sha256).
        let expectedPins = (pinHashes[host] ?? []).union(tofuPins(for: host))

        guard let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              !certChain.isEmpty else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        var matched = false
        var chainHashes: [String] = []
        for cert in certChain {
            if let publicKey = SecCertificateCopyKey(cert),
               let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? {
                let hash = SHA256.hash(data: publicKeyData)
                let base64Hash = Data(hash).base64EncodedString()
                chainHashes.append(base64Hash)
                if expectedPins.contains(base64Hash) {
                    matched = true
                    break
                }
            }
        }

        if matched {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else if isTofuEnabled, let firstHash = chainHashes.first {
            // H6: TOFU fallback — TLS passed but no pin matched.
            // Certificate likely rotated. Store new leaf pin and allow connection.
            logger.warning("Pin mismatch for \(host) — TOFU accepting new pin: \(firstHash)")
            saveTofuPin(firstHash, for: host)
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            // Pin mismatch, TOFU disabled — reject to enforce pinning.
            // If pins become stale after certificate rotation, users can enable
            // TOFU in Settings → Sicherheit as an escape hatch.
            logger.error("Pin mismatch for \(host), TOFU disabled. Rejecting connection. Chain hashes: \(chainHashes)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
