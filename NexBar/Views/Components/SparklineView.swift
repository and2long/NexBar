import SwiftUI

struct SparklineSeries {
    let values: [Double]
    let color: Color
    let fillOpacity: Double

    init(values: [Double], color: Color, fillOpacity: Double = 0.16) {
        self.values = values
        self.color = color
        self.fillOpacity = fillOpacity
    }
}

struct SparklineView: View {
    let series: [SparklineSeries]
    var maxValue: Double?

    var body: some View {
        Canvas { context, size in
            guard size.width > 1, size.height > 1 else { return }

            let computedMax = maxValue ?? max(
                series.flatMap(\.values).max() ?? 1,
                1
            )
            let ceiling = max(computedMax, 0.0001)

            // Draw subtle horizontal guide lines
            for fraction in [0.25, 0.5, 0.75] {
                let y = size.height * fraction
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)
            }

            for item in series {
                let points = item.values
                guard points.count >= 2 else { continue }

                let stepX = size.width / CGFloat(points.count - 1)
                var linePath = Path()
                var fillPath = Path()

                for (idx, rawValue) in points.enumerated() {
                    let normalized = min(1, max(0, rawValue / ceiling))
                    let x = CGFloat(idx) * stepX
                    let y = size.height - CGFloat(normalized) * (size.height - 4) - 2
                    let pt = CGPoint(x: x, y: y)

                    if idx == 0 {
                        linePath.move(to: pt)
                        fillPath.move(to: CGPoint(x: x, y: size.height))
                        fillPath.addLine(to: pt)
                    } else {
                        linePath.addLine(to: pt)
                        fillPath.addLine(to: pt)
                    }
                }

                fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                fillPath.closeSubpath()

                if item.fillOpacity > 0 {
                    context.fill(
                        fillPath,
                        with: .linearGradient(
                            Gradient(colors: [
                                item.color.opacity(item.fillOpacity),
                                item.color.opacity(0.01)
                            ]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: size.height)
                        )
                    )
                }

                context.stroke(
                    linePath,
                    with: .color(item.color),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}
