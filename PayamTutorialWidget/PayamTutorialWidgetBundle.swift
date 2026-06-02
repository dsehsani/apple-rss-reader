//
//  PayamTutorialWidgetBundle.swift
//  PayamTutorialWidget
//
//  Bundle entry point — registers only the Live Activity used by the
//  Payam onboarding tour. No home-screen widget or Control Center widget.
//

import SwiftUI
import WidgetKit

@main
struct PayamTutorialWidgetBundle: WidgetBundle {
    var body: some Widget {
        PayamTutorialWidgetLiveActivity()
    }
}
