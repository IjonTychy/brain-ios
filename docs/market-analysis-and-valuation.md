# brain-ios — Marktanalyse, Bewertung & Patentrecherche

> Erstellt: 23.03.2026 | Recherche via Web-Quellen und Marktdaten

---

## 1. Vergleichbare Apps & Preismodelle

### Produktivitäts-Apps (Einmalkauf)

| App | Modell | Preis | Anmerkung |
|-----|--------|-------|-----------|
| **Things 3** | Einmalkauf | ~$80 total (iPhone $10 + iPad $20 + Mac $50) | Nächstes Modell zu brain-ios |
| **GoodNotes** | Einmalkauf | $9.99 (alt) → jetzt Abo | Wechsel zeigt Markttrend |
| **Notefile** | Einmalkauf | $4.99 | Nischen-Notiz-App |

### Produktivitäts-Apps (Abo)

| App | Preis/Jahr | Anmerkung |
|-----|-----------|-----------|
| **Bear** | $30/Jahr | Markdown-Notizen, Apple-only |
| **Obsidian Sync** | $96/Jahr | Local-First Knowledge Management |
| **Craft** | $144/Jahr ($12/Mt.) | Visuelle Dokumente |
| **Notion** | $96–216/Jahr pro User | Cloud Workspace + AI |
| **Fantastical** | $40–57/Jahr | Kalender |
| **Todoist** | $48/Jahr | Task Management |

### KI-Apps

| App | Modell | Preis |
|-----|--------|-------|
| **ChatGPT Plus** | Abo | $20/Mt. |
| **Claude Pro** | Abo | $20/Mt. |
| **Gemini Advanced** | Abo | $20/Mt. |
| **Private LLM** | Einmalkauf | $5–15 |
| **Enclave AI** | Einmalkauf | ~$10 |

### Preisempfehlung für brain-ios

| Strategie | Preis | Begründung |
|-----------|-------|------------|
| **Konservativ** | CHF 29.99–49.99 | Konkurrenzfähig mit Things 3, unterbietet Jahresabos |
| **Premium** | CHF 59.99–79.99 | Gerechtfertigt durch KI + Multi-LLM + Runtime Engine |
| **Abo-Alternative** | CHF 4.99–9.99/Mt. | Falls Einmalkauf nicht funktioniert |

**Entscheidung laut ARCHITECTURE.md:** Einmalkauf, kein Abo.

---

## 2. App-Bewertung

### Methode 1: Nachbaukosten (Development Replacement Cost)

| Faktor | Wert |
|--------|------|
| Lines of Code | ~45'000 LOC Swift |
| Geschätzte Arbeitsstunden | 500–800h |
| Stundensatz Senior iOS Engineer (CH) | CHF 150–200/h |
| **Nachbaukosten** | **CHF 75'000 – 160'000** |

### Methode 2: Technologie-Asset-Wert (Pre-Revenue)

| Komponente | Wert |
|-----------|------|
| Runtime Engine (JSON → native SwiftUI) | Vergleichbar mit DivKit (Yandex), Ghost (Airbnb) — Teams von 5-15 Ingenieuren, 1-2 Jahre |
| Multi-LLM Router (5 Provider) | Einzigartig im Consumer-Bereich |
| 23 iOS Bridges, 158 Handler, 121 Tools | Breite Plattformintegration |
| Skill-Compiler (.brainskill.md → JSON) | Kein direktes Äquivalent am Markt |
| **Pre-Revenue Asset-Wert** | **CHF 50'000 – 150'000** |

### Methode 3: Umsatz-Multiples (bei Traction)

| MRR | Multiple | Bewertung |
|-----|----------|-----------|
| $1K MRR | 24–40x | $24'000 – $40'000 |
| $5K MRR | 2–4x Jahresumsatz | $120'000 – $240'000 |
| $15K MRR | 3–5x Jahresumsatz | $540'000 – $900'000 |

### Methode 4: Strategische Akquisition

| Käufertyp | Bewertung | Beispiele |
|-----------|-----------|----------|
| Indie-App-Käufer (Flippa) | $50'000 – $200'000 | Basierend auf realen Flippa-Verkäufen |
| Strategischer Käufer (Tech) | $500'000 – $5M+ | SDUI-Technologie + KI-Integration |
| Acqui-Hire | $200'000 – $500'000 | Team + Technologie |

### Reale Verkaufspreise (Indie-Apps)

| App | Monatsumsatz | Verkaufspreis | Multiple |
|-----|-------------|---------------|----------|
| Xnapper (Screenshot-Tool) | ~$4K/Mt. | $150'000 | 3.1x Jahresumsatz |
| Black Magic (Twitter Analytics) | $14K/Mt. | $128'000 | 0.76x Jahresumsatz |
| Freelancer PM Tool | $19.5K/Mt. | $240'000 | 1.0x Jahresumsatz |
| Mobile Game | ~$6K/Mt. Profit | $180'000 | 2.5x Jahresprofit |

### Zusammenfassung Bewertung

| Dimension | Spanne |
|-----------|--------|
| **Nachbaukosten** | CHF 75'000 – 160'000 |
| **Pre-Revenue Asset-Wert** | CHF 50'000 – 150'000 |
| **Bei $5K MRR** | CHF 120'000 – 240'000 |
| **Strategische Akquisition** | CHF 200'000 – 5'000'000+ |

---

## 3. Technologie-Alleinstellungsmerkmale (IP-Wert)

### Was brain-ios technisch einzigartig macht

| Technologie | Vergleichbar | Differenzierung |
|-----------|-----------|-----------------|
| **Runtime Engine (JSON → native SwiftUI)** | Airbnb Ghost, Yandex DivKit, Zalando AppCraft | KI-generierte Skills aus natürlicher Sprache |
| **Multi-LLM Router (5 Provider)** | LiteLLM, OpenRouter | On-Device + Cloud, Privacy-Zone-aware Routing |
| **Offline-First KI-Assistent** | Enclave AI, Private LLM, Locally AI | Vollständiges Knowledge Management + Skill-System |
| **Skill-Compiler (.brainskill.md → JSON)** | Kein direktes Äquivalent | Markdown-Spezifikation → KI-Kompilierung → Runtime-Ausführung |

### Potenziell patentierbare Ansprüche

1. Verfahren zur KI-gesteuerten Generierung nativer mobiler UIs aus natürlichsprachlichen Spezifikationen
2. Privacy-Zone-basiertes LLM-Routing für persönliche Datenverarbeitung
3. Runtime Skill Engine mit vorkompilierter Primitive-Komposition

---

## 4. Patentanmeldung Schweiz

### Amtliche Gebühren (IGE)

| Posten | Kosten |
|--------|--------|
| Anmeldung | CHF 200 |
| Prüfung | CHF 500 |
| Jahresgebühr ab 4. Jahr | CHF 100 (steigend) |
| Zusätzliche Ansprüche (>10) | CHF 50/Anspruch |
| **10 Jahre Patentschutz** | **CHF 1'180 total** |
| **20 Jahre Patentschutz** | **~CHF 7'620 total** |

### Gesamtkosten (mit Patentanwalt)

| Variante | Kosten |
|----------|--------|
| **Schweizer Patent (IGE)** | CHF 7'000 – 12'000 |
| **Europäisches Patent (EPA)** | CHF 15'000 – 25'000 |
| **Internationale PCT-Anmeldung** | CHF 20'000 – 40'000+ |

### Software-Patentierbarkeit

- Software "als solche" ist in CH/Europa **nicht patentierbar**
- Software mit **technischem Beitrag** ist patentierbar
- KI-Erfindungen sind patentierbar bei **konkreter technischer Anwendung**
- brain-ios Runtime Engine könnte als **technisches Verfahren** qualifizieren (dynamische UI-Generierung aus natürlichsprachlichen Spezifikationen auf mobilen Geräten)
- Alternative: **Geheimnisschutz** (Trade Secret) — kostenlos, aber kein Exklusivrecht

### Schweizer Patent: Wichtiger Hinweis

Das IGE prüft aktuell **nicht** auf Neuheit und erfinderische Tätigkeit (reines "Registrierungspatent"). Bei einem Rechtsstreit muss man die Gültigkeit selbst beweisen. Ab **2027** wird eine vollständige Prüfung optional möglich (Patentgesetzrevision).

### Patentoptionen für brain-ios

| Option | Kosten | Schutzumfang | Empfehlung |
|--------|--------|-------------|------------|
| **Schweizer Patent (IGE)** | CHF 7'000–12'000 | CH + LI, keine Neuheitsprüfung | Günstig, aber schwacher Schutz |
| **Europäisches Patent (EPA)** | CHF 15'000–25'000 | 38 Staaten, Neuheitsprüfung | Stärkster Schutz in Europa |
| **Warten auf CH-Revision 2027** | – | Dann Neuheitsprüfung beim IGE | Sinnvoll wenn kein Zeitdruck |
| **US Provisional Patent** | ~$2'000–5'000 | 12 Monate Prioritätsdatum (USA) | Sichert Priority Date günstig |
| **Geheimnisschutz** | CHF 0 | Kein Register, kein Exklusivrecht | Kostenlos, aber kein Schutz gegen Nachahmung |

---

## 5. Marktgrösse

### Relevante Märkte

| Markt | 2026 | 2030+ | CAGR |
|-------|------|-------|------|
| Knowledge Management Software | $16–26 Mrd. | $74 Mrd. (2034) | 12–18% |
| KI-Produktivitätstools | $10–17 Mrd. | $26–41 Mrd. | 16–28% |
| iOS App Store (gesamt) | $185 Mrd. | – | – |

### Adressierbarer Markt für brain-ios

| Segment | Geschätzte Grösse |
|---------|-------------------|
| Personal Knowledge Management (Consumer) | $2–4 Mrd. |
| Privacy-fokussierte KI-Tools | $500M–$1 Mrd. |
| Premium Einmalkauf iOS-Produktivität | $200–500M |
| **Realistischer SAM** | **$50–200M** |

Zielgruppe: Tech-affine, privacy-bewusste Apple-User, die CHF 30–80 für ein Premium-Tool zahlen.

---

## 6. Quellen

### Pricing & Markt
- [Adapty: App Pricing Models 2026](https://adapty.io/blog/app-pricing-models/)
- [Business of Apps: App Pricing Benchmarks](https://www.businessofapps.com/data/app-pricing/)
- [RevenueCat: AI Subscription App Pricing](https://www.revenuecat.com/blog/growth/ai-subscription-app-pricing/)
- [AIonX: AI Pricing Comparison 2026](https://aionx.co/ai-comparisons/ai-pricing-comparison/)
- [Foresight Mobile: Mobile App Economy 2026](https://foresightmobile.com/blog/mobile-app-economy-2026-monetisation-ai-foldables)

### Bewertung & Verkauf
- [RevenueCat: What App Buyers Really Want](https://www.revenuecat.com/blog/growth/guide-to-selling-apps/)
- [ClearlyAcquired: EBITDA Multiples SaaS 2025-2026](https://www.clearlyacquired.com/blog/ebitda-multiples-for-saas-and-software-companies-2025-2026)
- [Flippa: Apps Ecosystem Worth $100BN](https://flippa.com/blog/state-of-the-industry-apps/)
- [Flippa: Trends in Online Business Acquisitions 2024](https://flippa.com/blog/trends-in-online-business-acquisitions-2024/)
- [The BPO Network: Who Is Buying Apps 2025](https://www.thebponetwork.com/blog/who%E2%80%99s-buying-apps-in-2025-and-what-they%E2%80%99re-looking-for)
- [Market Clarity: Top 15 Most Profitable Indie Apps](https://mktclarity.com/blogs/news/indie-apps-top)

### Marktgrösse
- [Fortune Business Insights: Knowledge Management Software Market](https://www.fortunebusinessinsights.com/knowledge-management-software-market-110376)
- [Grand View Research: AI Productivity Tools Market](https://www.grandviewresearch.com/industry-analysis/ai-productivity-tools-market-report)

### Technologie-Vergleich
- [Stac: How Top Tech Companies Use Server-Driven UI](https://stac.dev/blogs/tech-companies-sdui)
- [Medium: Server-Driven UI Airbnb Netflix Lyft](https://medium.com/@aubreyhaskett/server-driven-ui-what-airbnb-netflix-and-lyft-learned-building-dynamic-mobile-experiences-20e346265305)

### Patent Schweiz
- [IGE: Kosten](https://www.ige.ch/de/uebersicht-geistiges-eigentum/ein-leitfaden-fuer-innovative-und-kreative/patente/kosten)
- [IGE: Gebühren Patente](https://www.ige.ch/de/etwas-schuetzen/patente/vor-der-anmeldung/kosten-und-gebuehren/gebuehren-patente)
- [IGE: Preis-Check Was kostet ein Patent?](https://www.ige.ch/de/blog/blog-artikel/preis-check-was-kostet-ein-patent)
- [IGE: Patentgesetzrevision](https://www.ige.ch/de/etwas-schuetzen/patente/anmeldung-in-der-schweiz/patentgesetzrevision)
- [BOHEST: Mindestkosten-Tarif 2025](https://www.bohest.ch/fileadmin/pdf/tarif-d.pdf)
- [Rentsch Partner: Software und Patente](https://www.rentschpartner.ch/patent-law/uebersicht/software-und-patente)
- [MW-PATENT: Softwarepatent](https://www.mw-patent.de/patentrecht/softwarepatent.html)
- [HSLU: Software Patentschutz](https://hub.hslu.ch/informatik/neue-software-was-sie-ueber-patentschutz-wissen-sollten/)
- [E. Blum: KI und Maschinelles Lernen](https://eblum.ch/de/technologiegebiete/kuenstliche-intelligenz-ki-maschinelles-lernen/)
- [PowerPatent: Valuation of AI Patents](https://powerpatent.com/blog/valuation-of-artificial-intelligence-patents)
