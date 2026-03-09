//
//  SafariView.swift
//  OpenRSS
//
//  UIViewControllerRepresentable wrapper around SFSafariViewController.
//  Cookies, stored credentials, and auto-fill are shared with Safari,
//  so signing into a paywalled site carries over to future visits.
//

import SafariServices
import SwiftUI

struct SafariView: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
