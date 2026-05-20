//
//  DeviceTokenService.swift
//  Payam
//
//  Registers the APNs device token with the Payam cloud
//  so the server can send silent push notifications on new feed items.
//

import Foundation

enum DeviceTokenService {

    private static let lastRegisteredTokenKey = "payam.device.lastRegisteredToken"

    /// Registers the device token with the cloud. Skips if already registered.
    static func register(tokenData: Data) async {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()

        // Skip if we already registered this exact token
        if hex == UserDefaults.standard.string(forKey: lastRegisteredTokenKey) {
            return
        }

        struct Body: Encodable {
            let deviceToken: String
            let bundleID: String
        }

        let body = Body(
            deviceToken: hex,
            bundleID: Bundle.main.bundleIdentifier ?? "com.payam"
        )

        do {
            try await PayamAPIClient.sendNoContent(
                path: "/v1/devices/register",
                body: body
            )
            UserDefaults.standard.set(hex, forKey: lastRegisteredTokenKey)
            print("☁️ Device token registered")
        } catch {
            print("☁️ Device token registration failed: \(error.localizedDescription)")
        }
    }
}
