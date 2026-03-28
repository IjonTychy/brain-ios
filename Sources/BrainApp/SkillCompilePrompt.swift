import Foundation

// Prompt templates for LLM-based skill compilation.
// The LLM reads a .brainskill.md and generates ScreenNode JSON.
// BrainTheme is the default — skills inherit the app's design unless they override it.
enum SkillCompilePrompt {

    // System prompt that teaches the LLM the ScreenNode JSON format.
    static let system = """
    Du bist ein Skill-Compiler für die brain-ios App. Du übersetzt .brainskill.md \
    Definitionen in ausführbares ScreenNode JSON.

    WICHTIG: Das JSON wird direkt vom SkillRenderer gerendert. Es muss gültig sein.

    ## ScreenNode Format
    Jeder Node hat: "type" (String), optional "properties" (Object), optional "children" (Array).

    ## Verfügbare UI-Typen (Primitives)
    Layout: stack, scroll, list, grid, tab-view, sheet, conditional, repeater, spacer, divider, section
    Content: text, image, icon, avatar, badge, markdown, label
    Input: text-field, text-editor, toggle, picker, slider, stepper, date-picker, color-picker, secure-field
    Interaction: button, link, menu, swipe-actions
    Data: stat-card, chart, progress, gauge, map, calendar-grid, empty-state, metric
    Feedback: toast, banner, loading
    System: open-url, copy-button, qr-code

    ## Properties
    - text: value, style (largeTitle/title/headline/subheadline/body/callout/caption), color (#hex), alignment
    - icon: name (SF Symbol), size, color (#hex)
    - button: title, action (String — Name der Action), icon, style (plain/bordered/borderedProminent)
    - stat-card: title, value, suffix
    - badge: text, color (#hex)
    - stack: direction (vertical/horizontal/z), spacing
    - grid: columns, spacing
    - conditional: condition (Expression-String)
    - repeater: data (Variable-Name), as (Item-Name)
    - text-field: placeholder, value ({{variable}})
    - empty-state: icon, title, message
    - image: source (SF Symbol oder https URL), width, height

    ## Expressions
    Variablen: {{variableName}}, {{item.property}}
    Filter: {{array | count}}, {{date | relative}}
    Vergleiche: "openTasks | count > 0"

    ## Design-Richtlinien (BrainTheme)
    - Verwende KEINE hardcodierten Farben ausser fuer spezifische Akzente
    - Der Renderer wendet automatisch BrainTheme-Defaults an (brandPurple, brandBlue, etc.)
    - Für Überschriften: style "headline" oder "title"
    - Für Untertitel: style "subheadline" oder "caption"
    - Icons: SF Symbols verwenden
    - stat-cards bekommen automatisch Material-Background und Schatten
    - Badges bekommen automatisch Capsule-Form mit brandPurple

    ## Ausgabeformat
    Antworte NUR mit dem JSON-Objekt. Kein Markdown, kein Text drumherum.
    Das JSON hat die Struktur: {"main": {<ScreenNode>}}
    """

    // Build the user prompt from a skill markdown.
    static func build(markdown: String) -> String {
        """
        Kompiliere den folgenden .brainskill.md Skill in ScreenNode JSON.
        Erstelle eine sinnvolle UI basierend auf der Beschreibung.
        Verwende die beschriebenen Screens, Aktionen und Datenquellen.

        ```markdown
        \(markdown)
        ```

        Antworte NUR mit dem JSON: {"main": {<ScreenNode>}}
        """
    }

    // Extract JSON from LLM response (strips markdown code fences if present).
    static func extractJSON(from response: String) -> String {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences
        if text.hasPrefix("```json") {
            text = String(text.dropFirst(7))
        } else if text.hasPrefix("```") {
            text = String(text.dropFirst(3))
        }
        if text.hasSuffix("```") {
            text = String(text.dropLast(3))
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate it's JSON
        guard text.hasPrefix("{"),
              let data = text.data(using: .utf8),
              let _ = try? JSONSerialization.jsonObject(with: data) else {
            return ""
        }
        return text
    }
}
