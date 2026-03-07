import SwiftUI
import Charts

struct SparklineView: View {
    let values: [Double]
    var color: Color = .accentColor

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                AreaMark(
                    x: .value("Index", index),
                    y: .value("Value", value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.2), color.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Index", index),
                    y: .value("Value", value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(color.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            // Latest value dot
            if let last = values.last {
                PointMark(
                    x: .value("Index", values.count - 1),
                    y: .value("Value", last)
                )
                .foregroundStyle(color)
                .symbolSize(16)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: yDomain)
    }

    private var yDomain: ClosedRange<Double> {
        guard let min = values.min(), let max = values.max(), min != max else {
            let mid = values.first ?? 0
            return (mid - 1)...(mid + 1)
        }
        let padding = (max - min) * 0.15
        return (min - padding)...(max + padding)
    }
}

#Preview {
    VStack(spacing: 20) {
        SparklineView(values: [68, 72, 70, 74, 72, 69, 72], color: .pink)
            .frame(height: 30)

        SparklineView(values: [120, 118, 122, 115, 118, 121], color: .red)
            .frame(height: 30)
    }
    .padding()
}
