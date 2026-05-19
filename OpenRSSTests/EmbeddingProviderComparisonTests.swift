//
//  EmbeddingProviderComparisonTests.swift
//  OpenRSSTests
//
//  Head-to-head benchmark: CoreML MiniLM-L6-v2 vs Apple NLEmbedding.
//
//  Uses a labeled dataset of 30 article pairs (15 same-story, 15 different-story)
//  to measure clustering accuracy at the 0.72 threshold used in SemanticClusterService.
//
//  Report is written to /tmp/embedding_comparison_report.txt
//

import Testing
import Foundation
@testable import OpenRSS

// MARK: - Labeled Pair

private struct LabeledPair {
    let textA: String
    let textB: String
    let isSameStory: Bool
    let tag: String
}

// MARK: - Test Dataset

private let labeledPairs: [LabeledPair] = [

    // ── SAME STORY (15 pairs) ──

    LabeledPair(
        textA: "Apple supplier Foxconn hit by ransomware attack stealing project files Foxconn confirmed a ransomware cyberattack on its U.S. factories",
        textB: "Foxconn confirms ransomware attack affected North American factories and Apple data The electronics manufacturer acknowledged a security breach",
        isSameStory: true, tag: "foxconn-ransomware"
    ),
    LabeledPair(
        textA: "SpaceX successfully lands Starship booster for the first time SpaceX achieved a historic milestone by landing the Super Heavy booster",
        textB: "SpaceX catches Starship rocket booster in historic first landing The Super Heavy booster was caught by the launch tower arms",
        isSameStory: true, tag: "spacex-starship-landing"
    ),
    LabeledPair(
        textA: "President signs landmark climate bill into law today The president signed a sweeping climate bill setting emissions targets for 2035",
        textB: "White House: president signs major climate legislation into law New law sets binding emissions reduction targets through 2035",
        isSameStory: true, tag: "climate-bill-signing"
    ),
    LabeledPair(
        textA: "Tesla recalls 500,000 vehicles over autopilot safety defect Tesla is recalling half a million cars due to a software issue",
        textB: "NHTSA orders Tesla recall of 500K cars for autopilot software bug Federal regulators issued a recall for Tesla vehicles with faulty autopilot",
        isSameStory: true, tag: "tesla-recall-autopilot"
    ),
    LabeledPair(
        textA: "Google unveils Gemini 2.0 AI model with improved reasoning Google announced its next-generation AI model at their annual conference",
        textB: "Google launches Gemini 2.0, its most capable AI model yet The new model shows significant improvements in reasoning and coding tasks",
        isSameStory: true, tag: "google-gemini-launch"
    ),
    LabeledPair(
        textA: "Ukraine strikes Russian ammunition depot in Crimea overnight A Ukrainian drone attack destroyed a major arms storage facility",
        textB: "Massive explosion at Crimean ammo dump after Ukrainian drone strike Satellite images confirm destruction of Russian ammunition warehouse",
        isSameStory: true, tag: "ukraine-crimea-strike"
    ),
    LabeledPair(
        textA: "OpenAI raises $6.6 billion in record funding round The AI startup is now valued at $157 billion after closing the deal",
        textB: "OpenAI closes $6.6B raise at $157 billion valuation The funding round was led by Thrive Capital with Microsoft participating",
        isSameStory: true, tag: "openai-funding"
    ),
    LabeledPair(
        textA: "Boeing Starliner crew stranded on ISS as return delayed again NASA announced another delay for the troubled Starliner capsule",
        textB: "NASA delays Boeing Starliner return from space station indefinitely The two astronauts will remain on the ISS while engineers troubleshoot",
        isSameStory: true, tag: "starliner-delay"
    ),
    LabeledPair(
        textA: "Samsung Galaxy S25 Ultra leaks reveal titanium design and AI features The upcoming flagship phone will feature a flat display and new AI",
        textB: "Leaked Galaxy S25 Ultra specs show titanium build and on-device AI Samsung's next flagship will reportedly use a flat screen design",
        isSameStory: true, tag: "samsung-s25-leak"
    ),
    LabeledPair(
        textA: "Amazon raises Prime subscription price by $20 effective next month Amazon will increase annual Prime membership from $139 to $159",
        textB: "Amazon Prime price hike: annual membership going up to $159 The increase takes effect next month for new subscribers",
        isSameStory: true, tag: "amazon-prime-price"
    ),
    LabeledPair(
        textA: "Meta lays off 10,000 employees in second round of cuts The company is eliminating roles across its Reality Labs and recruiting teams",
        textB: "Facebook parent Meta cuts 10,000 jobs in fresh layoff round CEO Zuckerberg calls it the year of efficiency as more roles are eliminated",
        isSameStory: true, tag: "meta-layoffs"
    ),
    LabeledPair(
        textA: "Fed holds interest rates steady citing persistent inflation The Federal Reserve kept rates unchanged at 5.25-5.50 percent",
        textB: "Federal Reserve pauses rate hikes as inflation remains stubborn The central bank held its benchmark rate steady at the current level",
        isSameStory: true, tag: "fed-rate-hold"
    ),
    LabeledPair(
        textA: "Earthquake of magnitude 7.2 strikes central Japan triggering tsunami warning A powerful earthquake shook Japan's coast early this morning",
        textB: "Major 7.2 earthquake hits Japan, tsunami advisory issued Authorities warned coastal residents to move to higher ground",
        isSameStory: true, tag: "japan-earthquake"
    ),
    LabeledPair(
        textA: "Netflix cracks down on password sharing in the United States Netflix has begun enforcing its new policy against sharing accounts",
        textB: "Netflix password sharing crackdown begins rolling out in US Subscribers will now need to verify their household to keep access",
        isSameStory: true, tag: "netflix-password-sharing"
    ),
    LabeledPair(
        textA: "Apple announces M4 MacBook Pro at October event The new MacBook Pro features the M4 chip with improved performance",
        textB: "New MacBook Pro with M4 chip unveiled at Apple's fall event Apple's latest laptop brings significant performance improvements",
        isSameStory: true, tag: "apple-m4-macbook"
    ),

    // ── DIFFERENT STORY (15 pairs) ──

    LabeledPair(
        textA: "Tesla recalls 500,000 vehicles over autopilot safety defect Tesla is recalling half a million cars due to a software issue",
        textB: "Ford recalls 300,000 trucks over brake issue in F-150 lineup Ford Motor Company announced a recall affecting its popular trucks",
        isSameStory: false, tag: "tesla-vs-ford-recall"
    ),
    LabeledPair(
        textA: "Apple announces M4 MacBook Pro at October event The new MacBook Pro features the M4 chip with improved performance",
        textB: "Apple releases iOS 19 beta with redesigned Control Center The latest iOS beta brings a completely new look to the notification system",
        isSameStory: false, tag: "apple-macbook-vs-ios"
    ),
    LabeledPair(
        textA: "Google unveils Gemini 2.0 AI model with improved reasoning Google announced its next-generation AI model at their annual conference",
        textB: "OpenAI releases GPT-5 with breakthrough reasoning capabilities The new model significantly outperforms its predecessor on benchmarks",
        isSameStory: false, tag: "google-ai-vs-openai-ai"
    ),
    LabeledPair(
        textA: "Meta lays off 10,000 employees in second round of cuts The company is eliminating roles across Reality Labs and recruiting",
        textB: "Google lays off hundreds from its advertising sales team The tech giant is restructuring its ad division amid AI shift",
        isSameStory: false, tag: "meta-layoffs-vs-google-layoffs"
    ),
    LabeledPair(
        textA: "SpaceX successfully lands Starship booster for the first time SpaceX achieved a historic milestone by catching the booster",
        textB: "Blue Origin launches New Glenn rocket on maiden flight Jeff Bezos's space company reached orbit for the first time",
        isSameStory: false, tag: "spacex-vs-blueorigin"
    ),
    LabeledPair(
        textA: "Earthquake of magnitude 7.2 strikes central Japan triggering tsunami A powerful earthquake shook Japan's coast early this morning",
        textB: "Typhoon Shanshan makes landfall in southern Japan causing flooding The category 4 storm brought destructive winds and heavy rain",
        isSameStory: false, tag: "japan-quake-vs-typhoon"
    ),
    LabeledPair(
        textA: "Samsung Galaxy S25 Ultra leaks reveal titanium design The upcoming flagship phone will feature a flat display",
        textB: "Samsung posts record quarterly profit on memory chip demand The company's semiconductor division drove strong earnings",
        isSameStory: false, tag: "samsung-phone-vs-earnings"
    ),
    LabeledPair(
        textA: "Amazon raises Prime subscription price by $20 Amazon will increase annual Prime membership to $159",
        textB: "Amazon Web Services launches new AI-powered cloud tools AWS announced several new machine learning services for developers",
        isSameStory: false, tag: "amazon-prime-vs-aws"
    ),
    LabeledPair(
        textA: "Fed holds interest rates steady citing persistent inflation The Federal Reserve kept rates unchanged at 5.25 percent",
        textB: "US unemployment falls to 3.4 percent in January jobs report The economy added 517,000 jobs far exceeding expectations",
        isSameStory: false, tag: "fed-rates-vs-jobs-report"
    ),
    LabeledPair(
        textA: "Netflix cracks down on password sharing in the United States Netflix has begun enforcing its policy against shared accounts",
        textB: "Disney+ gains 12 million subscribers beating Wall Street estimates The streaming service saw strong growth in international markets",
        isSameStory: false, tag: "netflix-vs-disney-streaming"
    ),
    LabeledPair(
        textA: "NASA launches Artemis IV mission to the Moon NASA successfully launched the Artemis IV rocket this morning",
        textB: "Manchester United signs striker in record transfer deal The club paid a fee of 100 million euros for the player",
        isSameStory: false, tag: "nasa-vs-football"
    ),
    LabeledPair(
        textA: "Ukraine strikes Russian ammunition depot in Crimea overnight A Ukrainian drone attack destroyed a major arms storage facility",
        textB: "Bitcoin surges past $100,000 for the first time The cryptocurrency hit an all-time high amid institutional buying",
        isSameStory: false, tag: "ukraine-vs-bitcoin"
    ),
    LabeledPair(
        textA: "President signs landmark climate bill into law today The sweeping legislation sets emissions targets for 2035",
        textB: "Supreme Court overturns Chevron doctrine in major ruling The decision limits federal agencies regulatory authority",
        isSameStory: false, tag: "climate-bill-vs-scotus"
    ),
    LabeledPair(
        textA: "Boeing Starliner crew stranded on ISS as return delayed NASA announced another delay for the troubled capsule",
        textB: "Airbus wins $50 billion deal to supply new planes to IndiGo The order is the largest single aircraft purchase in history",
        isSameStory: false, tag: "starliner-vs-airbus-deal"
    ),
    LabeledPair(
        textA: "OpenAI raises $6.6 billion in record funding round The AI startup is now valued at $157 billion",
        textB: "Stripe processes $1 trillion in payments for the first time The fintech company hit the milestone as e-commerce grows",
        isSameStory: false, tag: "openai-funding-vs-stripe"
    ),
]

// MARK: - Comparison Test Suite

@Suite("Embedding Provider Comparison")
struct EmbeddingProviderComparisonTests {

    private static let threshold: Float = 0.72

    private struct ProviderResult {
        let name: String
        let similarities: [(tag: String, similarity: Float, label: Bool)]
        let meanLatencyMs: Double
    }

    private func runProvider(
        _ provider: any EmbeddingProvider,
        name: String
    ) -> ProviderResult? {
        _ = provider.embed("warmup text for initialization")

        var similarities: [(tag: String, similarity: Float, label: Bool)] = []
        let start = CFAbsoluteTimeGetCurrent()
        var embedCount = 0

        for pair in labeledPairs {
            guard let vecA = provider.embed(pair.textA),
                  let vecB = provider.embed(pair.textB) else {
                continue
            }
            embedCount += 2
            let sim = SemanticClusterService.cosineSimilarity(vecA, vecB)
            similarities.append((pair.tag, sim, pair.isSameStory))
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let perEmbed = embedCount > 0 ? elapsed / Double(embedCount) : 0

        guard similarities.count == labeledPairs.count else { return nil }
        return ProviderResult(name: name, similarities: similarities, meanLatencyMs: perEmbed)
    }

    private func metrics(
        _ result: ProviderResult,
        threshold: Float
    ) -> (precision: Double, recall: Double, f1: Double,
          meanSame: Float, meanDiff: Float, gap: Float,
          tp: Int, fp: Int, fn: Int, tn: Int)
    {
        let same = result.similarities.filter { $0.label }
        let diff = result.similarities.filter { !$0.label }
        let meanSame = same.map(\.similarity).reduce(0, +) / Float(same.count)
        let meanDiff = diff.map(\.similarity).reduce(0, +) / Float(diff.count)
        let tp = same.filter { $0.similarity >= threshold }.count
        let fn = same.filter { $0.similarity < threshold }.count
        let fp = diff.filter { $0.similarity >= threshold }.count
        let tn = diff.filter { $0.similarity < threshold }.count
        let p = tp + fp > 0 ? Double(tp) / Double(tp + fp) : 0
        let r = tp + fn > 0 ? Double(tp) / Double(tp + fn) : 0
        let f1 = p + r > 0 ? 2 * p * r / (p + r) : 0
        return (p, r, f1, meanSame, meanDiff, meanSame - meanDiff, tp, fp, fn, tn)
    }

    // MARK: - Head-to-Head Comparison

    @Test("Head-to-head: CoreML MiniLM vs NLEmbedding on 30 labeled pairs")
    func headToHeadComparison() {
        let coreML = CoreMLEmbeddingProvider()
        let nlEmbed = NLEmbeddingProvider()

        guard coreML != nil || nlEmbed != nil else {
            Issue.record("Neither provider available")
            return
        }

        var results: [ProviderResult] = []
        if let p = coreML, let r = runProvider(p, name: "CoreML MiniLM") { results.append(r) }
        if let p = nlEmbed, let r = runProvider(p, name: "NLEmbedding") { results.append(r) }

        // Build report
        var lines: [String] = []
        lines.append(String(repeating: "=", count: 78))
        lines.append("EMBEDDING PROVIDER COMPARISON — 30 labeled pairs, threshold = \(Self.threshold)")
        lines.append(String(repeating: "=", count: 78))

        for result in results {
            let m = metrics(result, threshold: Self.threshold)
            lines.append("")
            lines.append("--- \(result.name) ---")
            lines.append("")
            lines.append("  Latency:    \(String(format: "%.2f", result.meanLatencyMs)) ms/embedding")
            lines.append("  Same-story mean similarity:      \(String(format: "%.4f", m.meanSame))")
            lines.append("  Different-story mean similarity:  \(String(format: "%.4f", m.meanDiff))")
            lines.append("  Separation gap:                   \(String(format: "%.4f", m.gap))")
            lines.append("")
            lines.append("  At threshold \(Self.threshold):")
            lines.append("    Precision:  \(String(format: "%.1f%%", m.precision * 100))  (TP=\(m.tp), FP=\(m.fp))")
            lines.append("    Recall:     \(String(format: "%.1f%%", m.recall * 100))  (TP=\(m.tp), FN=\(m.fn))")
            lines.append("    F1 Score:   \(String(format: "%.1f%%", m.f1 * 100))")
            lines.append("    True Neg:   \(m.tn)/15")
            lines.append("")
            lines.append("  Per-pair breakdown (sorted by similarity):")
            lines.append("  " + String(repeating: "-", count: 64))
            let sorted = result.similarities.sorted { $0.similarity > $1.similarity }
            for entry in sorted {
                let marker = entry.label ? "SAME " : "DIFF "
                let hit = entry.similarity >= Self.threshold
                let verdict = (entry.label == hit) ? " OK" : " WRONG"
                lines.append("    \(marker) \(String(format: "%.4f", entry.similarity))  \(entry.tag)\(verdict)")
            }
        }

        if results.count == 2 {
            let m0 = metrics(results[0], threshold: Self.threshold)
            let m1 = metrics(results[1], threshold: Self.threshold)
            lines.append("")
            lines.append(String(repeating: "=", count: 78))
            lines.append("SUMMARY")
            lines.append(String(repeating: "=", count: 78))
            let col0 = results[0].name.padding(toLength: 20, withPad: " ", startingAt: 0)
            let col1 = results[1].name
            lines.append("                      \(col0) \(col1)")
            lines.append("  F1 Score:           \(String(format: "%.1f%%", m0.f1 * 100).padding(toLength: 20, withPad: " ", startingAt: 0)) \(String(format: "%.1f%%", m1.f1 * 100))")
            lines.append("  Precision:          \(String(format: "%.1f%%", m0.precision * 100).padding(toLength: 20, withPad: " ", startingAt: 0)) \(String(format: "%.1f%%", m1.precision * 100))")
            lines.append("  Recall:             \(String(format: "%.1f%%", m0.recall * 100).padding(toLength: 20, withPad: " ", startingAt: 0)) \(String(format: "%.1f%%", m1.recall * 100))")
            lines.append("  Separation gap:     \(String(format: "%.4f", m0.gap).padding(toLength: 20, withPad: " ", startingAt: 0)) \(String(format: "%.4f", m1.gap))")
            lines.append("  Latency:            \(String(format: "%.2f ms", results[0].meanLatencyMs).padding(toLength: 20, withPad: " ", startingAt: 0)) \(String(format: "%.2f ms", results[1].meanLatencyMs))")
            let f1diff = abs(m0.f1 - m1.f1) * 100
            let winner = m0.f1 >= m1.f1 ? results[0].name : results[1].name
            if f1diff < 5 {
                lines.append("  Verdict: Statistically similar (< 5 F1 points apart)")
            } else {
                lines.append("  Verdict: \(winner) wins by \(String(format: "%.1f", f1diff)) F1 points")
            }

            // Threshold sweep
            lines.append("")
            lines.append(String(repeating: "=", count: 78))
            lines.append("THRESHOLD SWEEP")
            lines.append(String(repeating: "=", count: 78))
            let thresholds: [Float] = stride(from: 0.40, through: 0.90, by: 0.05).map { Float($0) }
            for result in results {
                lines.append("")
                lines.append("  \(result.name):")
                lines.append("  Threshold   Precision   Recall      F1")
                lines.append("  " + String(repeating: "-", count: 50))
                var bestF1: Double = 0
                var bestT: Float = 0
                for t in thresholds {
                    let m = metrics(result, threshold: t)
                    let mark = abs(t - Self.threshold) < 0.001 ? " << current" : ""
                    lines.append("    \(String(format: "%.2f", t))       \(String(format: "%5.1f%%", m.precision * 100))     \(String(format: "%5.1f%%", m.recall * 100))   \(String(format: "%5.1f%%", m.f1 * 100))\(mark)")
                    if m.f1 > bestF1 { bestF1 = m.f1; bestT = t }
                }
                lines.append("  Best: threshold=\(String(format: "%.2f", bestT)), F1=\(String(format: "%.1f%%", bestF1 * 100))")
            }
        }

        // Write report to /tmp so we can read it from host
        let report = lines.joined(separator: "\n")
        try? report.write(toFile: "/tmp/embedding_comparison_report.txt", atomically: true, encoding: .utf8)

        // Assertions
        for result in results {
            let m = metrics(result, threshold: Self.threshold)
            #expect(m.f1 > 0, "\(result.name) should achieve non-zero F1")
        }
    }
}
