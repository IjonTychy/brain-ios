import Foundation
import BrainCore
#if canImport(os)
import os.log
#endif

// Loads bundled .brainskill.md files from the app bundle at startup.
// Only installs skills that have screens_json (functional UI).
// Skills without screens_json are skipped (they would be useless).
struct SkillBundleLoader {

    #if canImport(os)
    private static let logger = Logger(subsystem: "com.example.brain-ios", category: "SkillBundleLoader")
    #endif

    static func loadBundledSkills(lifecycle: SkillLifecycle) {
        guard let skillURLs = Bundle.main.urls(
            forResourcesWithExtension: "md",
            subdirectory: nil
        )?.filter({ $0.lastPathComponent.hasSuffix(".brainskill.md") })
        else { return }

        let parser = BrainSkillParser()
        var installed = 0
        var skipped = 0

        for url in skillURLs {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            do {
                let source = try parser.parse(content)

                // Language skills (category: "language") don't need screens — they provide labels.
                let isLanguageSkill = source.id.hasPrefix("brain-language-")

                // Skip non-language skills without screens_json — they have no UI and are useless
                if !isLanguageSkill {
                    guard let screensJSON = source.screensJSON, !screensJSON.isEmpty else {
                        skipped += 1
                        continue
                    }
                }

                // Only install if not present, version is newer, or existing has empty screens
                if let existing = try lifecycle.fetch(id: source.id) {
                    let needsRepair = !existing.hasScreens && source.screensJSON != nil
                    if existing.version >= source.version && !needsRepair {
                        skipped += 1
                        continue
                    }
                    try lifecycle.uninstall(id: source.id)
                }

                try lifecycle.installFromSource(
                    source: source,
                    createdBy: .system,
                    screensJSON: isLanguageSkill ? "{}" : source.screensJSON,
                    actionsJSON: source.actionsJSON
                )
                installed += 1
            } catch {
                #if canImport(os)
                logger.error("Skill bundle load failed: \(url.lastPathComponent): \(error)")
                #endif
            }
        }

        #if canImport(os)
        if installed > 0 || skipped > 0 {
            logger.info("Skills: \(installed) installed, \(skipped) skipped")
        }
        #endif
    }
}
