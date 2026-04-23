//
//  HelloDrawView.swift
//  OpenRSS
//
//  Animates the "hello" SVG as a hand-drawn stroke with Apple's colorful gradient,
//  then fades in today's date once the drawing completes.
//

import SwiftUI

// MARK: - HelloDrawView

struct HelloDrawView: View {

    /// Rendered height of the "hello" script; width is derived from the 638 × 200 SVG ratio.
    var height: CGFloat = 36

    @State private var p1: CGFloat = 0   // 'h' draw progress
    @State private var p2: CGFloat = 0   // 'ello' draw progress
    @State private var showDate = false

    private var scale:     CGFloat { height / 200 }
    private var width:     CGFloat { height * 638 / 200 }
    private var lineWidth: CGFloat { 14.8883 * scale }

    private static let gradient = LinearGradient(
        colors: [
            Color(red: 0.18, green: 0.56, blue: 1.00),
            Color(red: 0.42, green: 0.26, blue: 0.96),
            Color(red: 0.84, green: 0.22, blue: 0.72),
            Color(red: 1.00, green: 0.36, blue: 0.22),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    private var weekdayString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: .now)
    }

    private var monthDayString: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f.string(from: .now)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Animated "hello" strokes — fades out once drawing completes
            ZStack {
                HelloStrokeH(scale: scale)
                    .trim(from: 0, to: p1)
                    .stroke(
                        Self.gradient,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )

                HelloStrokeEllo(scale: scale)
                    .trim(from: 0, to: p2)
                    .stroke(
                        Self.gradient,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
            }
            .frame(width: width, height: height)
            .opacity(showDate ? 0 : 1)

            // Hero date — fades in to replace "hello"
            VStack(alignment: .leading, spacing: 1) {
                Text(weekdayString)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(.primary)
                Text(monthDayString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .opacity(showDate ? 1 : 0)
            .offset(y: showDate ? 0 : 8)
        }
        .onAppear {
            // 'h' draws in 0.55 s, starting after a 0.1 s pause
            withAnimation(.easeOut(duration: 0.55).delay(0.1))  { p1 = 1 }
            // 'ello' picks up and draws in 1.1 s
            withAnimation(.easeOut(duration: 1.1).delay(0.55))  { p2 = 1 }
            // Hello fades out, hero date fades in — slower for elegance
            withAnimation(.easeOut(duration: 0.9).delay(1.75))  { showDate = true }
        }
    }
}

// MARK: - Stroke Shapes

private struct HelloStrokeH: Shape {
    let scale: CGFloat
    func path(in rect: CGRect) -> Path {
        let s = scale
        var p = Path()
        p.move(to:      .init(x: 8.69141 * s, y: 166.606 * s))
        p.addCurve(to:  .init(x: 89.8184 * s, y: 98.0823 * s),
                   control1: .init(x: 36.2386 * s, y: 151.292 * s),
                   control2: .init(x: 61.3402 * s, y: 131.601 * s))
        p.addCurve(to:  .init(x: 120.121 * s, y: 31.0553 * s),
                   control1: .init(x: 109.203 * s, y: 75.2016 * s),
                   control2: .init(x: 119.625 * s, y: 49.0755 * s))
        p.addCurve(to:  .init(x: 101.759 * s, y: 7.49156 * s),
                   control1: .init(x: 120.369 * s, y: 17.6563 * s),
                   control2: .init(x: 113.836 * s, y: 7.49156 * s))
        p.addCurve(to:  .init(x: 74.7114 * s, y: 40.9891 * s),
                   control1: .init(x: 88.3591 * s, y: 7.49156 * s),
                   control2: .init(x: 79.9224 * s, y: 17.6563 * s))
        p.addCurve(to:  .init(x: 54.1159 * s, y: 190.409 * s),
                   control1: .init(x: 69.0042 * s, y: 66.632  * s),
                   control2: .init(x: 64.7859 * s, y: 96.0563 * s))
        return p
    }
}

private struct HelloStrokeEllo: Shape {
    let scale: CGFloat
    func path(in rect: CGRect) -> Path {
        let s = scale
        var p = Path()
        p.move(to:     .init(x: 55.1621 * s, y: 181.188 * s))
        p.addCurve(to: .init(x: 107.962 * s, y:  98.1009 * s),
                   control1: .init(x:  60.6248 * s, y: 133.167  * s),
                   control2: .init(x:  81.4116 * s, y:  98.1009 * s))
        p.addCurve(to: .init(x: 131.071 * s, y: 128.87  * s),
                   control1: .init(x: 123.843  * s, y:  98.1009 * s),
                   control2: .init(x: 133.936  * s, y: 110.756  * s))
        p.addCurve(to: .init(x: 125.408 * s, y: 163.113 * s),
                   control1: .init(x: 129.457  * s, y: 139.54   * s),
                   control2: .init(x: 127.587  * s, y: 150.458  * s))
        p.addCurve(to: .init(x: 152.122 * s, y: 191.401 * s),
                   control1: .init(x: 122.869  * s, y: 178.994  * s),
                   control2: .init(x: 130.128  * s, y: 191.401  * s))
        p.addCurve(to: .init(x: 237.097 * s, y: 145.968 * s),
                   control1: .init(x: 184.197  * s, y: 191.401  * s),
                   control2: .init(x: 219.189  * s, y: 173.576  * s))
        p.addCurve(to: .init(x: 245.928 * s, y: 119.937 * s),
                   control1: .init(x: 243.198  * s, y: 136.562  * s),
                   control2: .init(x: 245.68   * s, y: 128.126  * s))
        p.addCurve(to: .init(x: 222.851 * s, y:  93.8826 * s),
                   control1: .init(x: 246.176  * s, y: 105.049  * s),
                   control2: .init(x: 237.739  * s, y:  93.8826 * s))
        p.addCurve(to: .init(x: 189.6   * s, y: 142.518 * s),
                   control1: .init(x: 203.992  * s, y:  93.8826 * s),
                   control2: .init(x: 189.6    * s, y: 115.223  * s))
        p.addCurve(to: .init(x: 239.208 * s, y: 192.394 * s),
                   control1: .init(x: 189.6    * s, y: 171.798  * s),
                   control2: .init(x: 205.481  * s, y: 192.394  * s))
        p.addCurve(to: .init(x: 359.198 * s, y:  75.9115 * s),
                   control1: .init(x: 285.065  * s, y: 192.394  * s),
                   control2: .init(x: 335.859  * s, y: 137.345  * s))
        p.addCurve(to: .init(x: 368.26  * s, y:  31.2042 * s),
                   control1: .init(x: 365.788  * s, y:  58.566  * s),
                   control2: .init(x: 368.26   * s, y:  42.4595 * s))
        p.addCurve(to: .init(x: 352.131 * s, y:   7.61121 * s),
                   control1: .init(x: 368.26   * s, y:  17.8586 * s),
                   control2: .init(x: 364.042  * s, y:   7.61121 * s))
        p.addCurve(to: .init(x: 325.828 * s, y:  30.9658 * s),
                   control1: .init(x: 340.469  * s, y:   7.61121 * s),
                   control2: .init(x: 332.776  * s, y:  16.6671 * s))
        p.addCurve(to: .init(x: 309.203 * s, y:  98.5079 * s),
                   control1: .init(x: 317.688  * s, y:  47.5497 * s),
                   control2: .init(x: 311.667  * s, y:  71.4692 * s))
        p.addCurve(to: .init(x: 349.936 * s, y: 191.401  * s),
                   control1: .init(x: 303      * s, y: 166.354  * s),
                   control2: .init(x: 316.895  * s, y: 191.401  * s))
        p.addCurve(to: .init(x: 457.285 * s, y:  75.7216 * s),
                   control1: .init(x: 389.999  * s, y: 191.401  * s),
                   control2: .init(x: 434.542  * s, y: 135.587  * s))
        p.addCurve(to: .init(x: 466.275 * s, y:  31.2042 * s),
                   control1: .init(x: 463.803  * s, y:  58.566  * s),
                   control2: .init(x: 466.275  * s, y:  42.4595 * s))
        p.addCurve(to: .init(x: 450.146 * s, y:   7.61121 * s),
                   control1: .init(x: 466.275  * s, y:  17.8586 * s),
                   control2: .init(x: 462.057  * s, y:   7.61121 * s))
        p.addCurve(to: .init(x: 423.843 * s, y:  30.9658 * s),
                   control1: .init(x: 438.484  * s, y:   7.61121 * s),
                   control2: .init(x: 430.791  * s, y:  16.6671 * s))
        p.addCurve(to: .init(x: 407.218 * s, y:  98.5079 * s),
                   control1: .init(x: 415.703  * s, y:  47.5497 * s),
                   control2: .init(x: 409.682  * s, y:  71.4692 * s))
        p.addCurve(to: .init(x: 444.416 * s, y: 191.401  * s),
                   control1: .init(x: 401.015  * s, y: 166.354  * s),
                   control2: .init(x: 414.91   * s, y: 191.401  * s))
        p.addCurve(to: .init(x: 499.471 * s, y: 138.455  * s),
                   control1: .init(x: 473.874  * s, y: 191.401  * s),
                   control2: .init(x: 489.877  * s, y: 165.723  * s))
        p.addCurve(to: .init(x: 544.935 * s, y:  94.8751 * s),
                   control1: .init(x: 508.955  * s, y: 111.5    * s),
                   control2: .init(x: 520.618  * s, y:  94.8751 * s))
        p.addCurve(to: .init(x: 580.915 * s, y: 137.803  * s),
                   control1: .init(x: 565.034  * s, y:  94.8751 * s),
                   control2: .init(x: 580.915  * s, y: 109.763  * s))
        p.addCurve(to: .init(x: 535.362 * s, y: 192.394  * s),
                   control1: .init(x: 580.915  * s, y: 168.821  * s),
                   control2: .init(x: 560.791  * s, y: 192.146  * s))
        p.addCurve(to: .init(x: 499.774 * s, y: 147.232  * s),
                   control1: .init(x: 512.983  * s, y: 192.642  * s),
                   control2: .init(x: 498.285  * s, y: 174.528  * s))
        p.addCurve(to: .init(x: 543.943 * s, y:  94.8751 * s),
                   control1: .init(x: 501.511  * s, y: 116.959  * s),
                   control2: .init(x: 519.873  * s, y:  94.8751 * s))
        p.addCurve(to: .init(x: 578.682 * s, y: 107.778  * s),
                   control1: .init(x: 557.838  * s, y:  94.8751 * s),
                   control2: .init(x: 569.51   * s, y: 101.052  * s))
        p.addCurve(to: .init(x: 630.047 * s, y:  96.7716 * s),
                   control1: .init(x: 603.549  * s, y: 125.919  * s),
                   control2: .init(x: 622.709  * s, y: 114.709  * s))
        return p
    }
}

// MARK: - Preview

#Preview {
    HelloDrawView(height: 52)
        .padding()
}
