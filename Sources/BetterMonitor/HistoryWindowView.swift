import SwiftUI

enum HistoryMode {
    case cpu
    case gpu
}

struct HistoryWindowView: View {
    let title: String
    let mode: HistoryMode
    @Bindable var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(store.snapshot.capturedAt == .distantPast ? "Waiting for sample" : MonitorFormatting.shortDate(store.snapshot.capturedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HistoryGraph(values: values, tint: tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 16) {
                ForEach(summaryItems, id: \.0) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.1)
                            .font(.callout.weight(.semibold))
                    }
                }
                Spacer()
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var tint: Color {
        switch mode {
        case .cpu: .blue
        case .gpu: .purple
        }
    }

    private var values: [Double] {
        switch mode {
        case .cpu:
            let cpu = store.snapshot.summary.cpu
            let history = store.history.values(for: .cpu)
            return history.isEmpty ? [cpu.systemPercent + cpu.userPercent] : history
        case .gpu:
            let gpuProcesses = store.snapshot.processes.filter(\.usesGPU)
            return gpuProcesses.isEmpty ? [0, 0, 0] : gpuProcesses.prefix(60).map(\.energyImpact)
        }
    }

    private var summaryItems: [(String, String)] {
        switch mode {
        case .cpu:
            let cpu = store.snapshot.summary.cpu
            return [
                ("System", MonitorFormatting.percent(cpu.systemPercent)),
                ("User", MonitorFormatting.percent(cpu.userPercent)),
                ("Idle", MonitorFormatting.percent(cpu.idlePercent)),
                ("Load", cpu.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " "))
            ]
        case .gpu:
            let gpu = store.snapshot.processes.filter(\.usesGPU)
            return [
                ("Processes", "\(gpu.count)"),
                ("Impact", String(format: "%.1f", gpu.reduce(0) { $0 + $1.energyImpact })),
                ("Top", gpu.max(by: { $0.energyImpact < $1.energyImpact })?.name ?? "None")
            ]
        }
    }
}

private struct HistoryGraph: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(values.max() ?? 1, 1)
            ZStack(alignment: .bottomLeading) {
                GridLines()
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)

                Path { path in
                    let step = proxy.size.width / CGFloat(max(values.count - 1, 1))
                    for index in values.indices {
                        let x = CGFloat(index) * step
                        let y = proxy.size.height - CGFloat(values[index] / maxValue) * proxy.size.height
                        if index == values.startIndex {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
        }
    }
}

private struct GridLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 1..<4 {
            let y = rect.height * CGFloat(index) / 4
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        for index in 1..<6 {
            let x = rect.width * CGFloat(index) / 6
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        return path
    }
}
