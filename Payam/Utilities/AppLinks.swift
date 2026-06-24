//
//  AppLinks.swift
//  Payam
//
//  Central registry of external URLs used throughout the app.
//  Update this file when URLs change rather than hunting for literals.
//

import Foundation

enum AppLinks {
    static let privacyPolicy = URL(string: "https://dsehsani.github.io/apple-rss-reader/privacy/")!

    /// Terms of Use. Defaults to Apple's standard EULA, which App Review accepts
    /// when an app does not provide its own custom terms. Swap for a hosted ToS
    /// page if/when one exists.
    static let termsOfService = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Support / report contact. Single source of truth — update here if the
    /// support address changes.
    static let supportEmail = "jlbetts@ucdavis.edu"

    /// Generic support mailto.
    static let support = mailto(subject: "Payam Support")

    /// Builds a mailto URL to report objectionable content. Pre-fills the source
    /// so reports are actionable. Used by the in-app "Report" actions (Guideline 1.2).
    static func reportContent(title: String, source: String) -> URL {
        let body = """
        I want to report the following content as objectionable or inappropriate:

        Article: \(title)
        Source: \(source)

        Reason:
        """
        return mailto(subject: "Report Content — Payam", body: body)
    }

    /// Builds a mailto URL with an optional pre-filled subject/body.
    static func mailto(subject: String, body: String = "") -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        var items = [URLQueryItem(name: "subject", value: subject)]
        if !body.isEmpty { items.append(URLQueryItem(name: "body", value: body)) }
        components.queryItems = items
        return components.url ?? URL(string: "mailto:\(supportEmail)")!
    }
}
