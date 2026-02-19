//
//  HeadingView.swift
//  OpenRSS
//
//  Phase 5 — renders a heading ContentNode.
//

import SwiftUI

struct HeadingView: View {

    let level: Int
    let text: String

    var body: some View {
        Text(text)
            .font(headingFont)
            .fontWeight(level <= 2 ? .bold : .semibold)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, topPadding)
    }

    private var headingFont: Font {
        switch level {
        case 1:  return .title
        case 2:  return .title2
        case 3:  return .title3
        case 4:  return .headline
        default: return .subheadline
        }
    }

    private var topPadding: CGFloat {
        level <= 2 ? 12 : 8
    }
}
