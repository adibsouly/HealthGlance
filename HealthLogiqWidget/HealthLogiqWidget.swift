import SwiftUI
import WidgetKit

struct HealthLogiqWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: HealthWidgetSnapshot
}

struct HealthLogiqWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HealthLogiqWidgetEntry {
        HealthLogiqWidgetEntry(date: Date(), snapshot: previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (HealthLogiqWidgetEntry) -> Void) {
        completion(HealthLogiqWidgetEntry(date: Date(), snapshot: HealthWidgetStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthLogiqWidgetEntry>) -> Void) {
        let entry = HealthLogiqWidgetEntry(date: Date(), snapshot: HealthWidgetStore.load())
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private var previewSnapshot: HealthWidgetSnapshot {
        HealthWidgetSnapshot(
            metrics: [
                HealthWidgetMetric(title: "Steps", value: "8,420", unit: "steps", systemImage: "figure.walk", trend: .positive),
                HealthWidgetMetric(title: "Activity Heart Rate", value: "118", unit: "bpm", systemImage: "heart.fill", trend: .stable),
                HealthWidgetMetric(title: "Sleep", value: "7.4", unit: "hr", systemImage: "bed.double.fill", trend: .positive),
                HealthWidgetMetric(title: "Body Battery", value: "82", unit: "%", systemImage: "battery.100percent", trend: .positive)
            ],
            generatedAt: Date()
        )
    }
}

struct HealthLogiqWidgetView: View {
    let entry: HealthLogiqWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if entry.snapshot.metrics.isEmpty {
                emptyState
            } else {
                switch family {
                case .systemSmall:
                    smallWidget
                case .systemMedium:
                    mediumWidget
                default:
                    largeWidget
                }
            }
        }
        .widgetURL(URL(string: "healthlogiq://dashboard"))
        .healthLogiqWidgetBackground()
    }

    private var smallWidget: some View {
        let metric = entry.snapshot.metrics.first

        return VStack(alignment: .leading, spacing: 10) {
            widgetHeader

            Spacer(minLength: 4)

            if let metric {
                Image(systemName: metric.systemImage)
                    .font(.title2)
                    .foregroundStyle(.white)

                Text(metric.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(metric.value)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)

                    Text(metric.unit)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }

                trendBadge(for: metric)
            }
        }
        .padding()
    }

    private var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader

            HStack(spacing: 10) {
                ForEach(Array(entry.snapshot.metrics.prefix(3))) { metric in
                    metricColumn(metric)
                }
            }
        }
        .padding()
    }

    private var largeWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(entry.snapshot.metrics.prefix(6))) { metric in
                    metricRow(metric)
                }
            }

            Spacer(minLength: 0)

            Text("Updated \(entry.snapshot.generatedAt, style: .time)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.68))
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            widgetHeader

            Spacer()

            Image(systemName: "heart.text.square")
                .font(.title2)
                .foregroundStyle(.white)

            Text("Open HealthLogiq")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Refresh Health data to update your widgets.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }

    private var widgetHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.circle.fill")
                .foregroundStyle(.white)

            Text("HealthLogiq")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)
        }
    }

    private func metricColumn(_ metric: HealthWidgetMetric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: metric.systemImage)
                .font(.headline)
                .foregroundStyle(.white)

            Text(metric.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)

            Text(metric.displayValue)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.72)
                .lineLimit(1)

            trendBadge(for: metric)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metricRow(_ metric: HealthWidgetMetric) -> some View {
        HStack(spacing: 8) {
            Image(systemName: metric.systemImage)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(metric.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                Text(metric.displayValue)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 2)

            trendIcon(for: metric)
        }
        .padding(9)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func trendBadge(for metric: HealthWidgetMetric) -> some View {
        if let trend = metric.trend {
            HStack(spacing: 4) {
                Image(systemName: trend.systemImage)
                Text(trendLabel(for: trend))
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(trendColor(for: trend).opacity(0.82), in: Capsule())
        }
    }

    @ViewBuilder
    private func trendIcon(for metric: HealthWidgetMetric) -> some View {
        if let trend = metric.trend {
            Image(systemName: trend.systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(5)
                .background(trendColor(for: trend).opacity(0.82), in: Circle())
        }
    }

    private func trendLabel(for trend: HealthWidgetTrend) -> String {
        switch trend {
        case .negative: return "Below"
        case .stable: return "Stable"
        case .positive: return "Above"
        }
    }

    private func trendColor(for trend: HealthWidgetTrend) -> Color {
        switch trend {
        case .negative: return .orange
        case .stable: return .blue
        case .positive: return .green
        }
    }
}

struct HealthLogiqMetricsWidget: Widget {
    let kind = "HealthLogiqMetricsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HealthLogiqWidgetProvider()) { entry in
            HealthLogiqWidgetView(entry: entry)
        }
        .configurationDisplayName("HealthLogiq Metrics")
        .description("See your latest HealthLogiq metrics and trends.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct HealthLogiqWidgetBundle: WidgetBundle {
    var body: some Widget {
        HealthLogiqMetricsWidget()
    }
}

private extension View {
    func healthLogiqWidgetBackground() -> some View {
        modifier(HealthLogiqWidgetBackgroundModifier())
    }
}

private struct HealthLogiqWidgetBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.42, blue: 0.72), Color(red: 0.02, green: 0.66, blue: 0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                for: .widget
            )
        } else {
            content.background(
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.42, blue: 0.72), Color(red: 0.02, green: 0.66, blue: 0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}
