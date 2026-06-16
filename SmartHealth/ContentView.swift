import Charts
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = HealthAgentViewModel()
    @State private var isChatVisible = false
    @State private var tileTheme: MetricTile.Theme = .classic
    @FocusState private var isComposerFocused: Bool

    private let metricColumns = [
        GridItem(.adaptive(minimum: 150), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dashboard

                if isChatVisible {
                    Divider()

                    chatPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                    composer
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("HealthLogiq")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            tileTheme = tileTheme == .classic ? .colorful : .classic
                        }
                    } label: {
                        Image(systemName: tileTheme == .classic ? "paintpalette" : "circle.lefthalf.filled")
                    }
                    .accessibilityLabel(tileTheme == .classic ? "Use colorful tiles" : "Use classic tiles")

                    Button {
                        toggleChat()
                    } label: {
                        Image(systemName: isChatVisible ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                    }
                    .accessibilityLabel(isChatVisible ? "Hide chat" : "Show chat")

                    Button {
                        Task { await viewModel.refreshFromButton() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoadingHealthData)
                    .accessibilityLabel("Refresh Health data")

                    NavigationLink {
                        AboutAppView()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("About the app")
                }
            }
            .task {
                if viewModel.metricCards.isEmpty {
                    await viewModel.connectHealth()
                }
            }
            .userActivity(AppMetadata.dashboardActivityType) { activity in
                AppMetadata.configureDashboardActivity(activity)
            }
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
                }

                if viewModel.metricCards.isEmpty {
                    emptyMetricsView
                } else {
                    LazyVGrid(columns: metricColumns, spacing: 12) {
                        ForEach(viewModel.metricCards) { metric in
                            NavigationLink {
                                MetricDetailView(metric: metric, tileTheme: tileTheme)
                            } label: {
                                MetricTile(metric: metric, theme: tileTheme)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Health Metrics")
                    .font(.title2.weight(.semibold))
                Text(viewModel.agentStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isLoadingHealthData {
                ProgressView()
            }
        }
    }

    private var emptyMetricsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Apple Health is not connected yet", systemImage: "heart")
                .font(.headline)
            Text("Grant read access so the agent can show steps, activity, heart rate, HRV, and sleep tiles from this iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                Task { await viewModel.connectHealth() }
            } label: {
                Label("Connect Health", systemImage: "heart.text.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoadingHealthData)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var chatPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    collapseChat()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide chat")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            chatTranscript
                .frame(maxHeight: 220)
        }
        .background(Color(.systemBackground))
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height > 40 {
                        collapseChat()
                    }
                }
        )
    }

    private var chatTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }

                    if viewModel.isSendingMessage {
                        HStack {
                            ProgressView()
                            Text("Thinking")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                guard let lastID = viewModel.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                toggleChat()
            } label: {
                Image(systemName: isChatVisible ? "chevron.down.circle" : "chevron.up.circle")
                    .font(.system(size: 24))
            }
            .accessibilityLabel(isChatVisible ? "Hide chat" : "Show chat")

            TextField("Ask about metrics", text: $viewModel.currentInput, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...2)
                .focused($isComposerFocused)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isChatVisible = true
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

            Button {
                Task {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isChatVisible = true
                    }
                    await viewModel.sendMessage()
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
            }
            .disabled(!viewModel.canSend)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func toggleChat() {
        if isChatVisible {
            collapseChat()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isChatVisible = true
            }
        }
    }

    private func collapseChat() {
        isComposerFocused = false
        withAnimation(.easeInOut(duration: 0.2)) {
            isChatVisible = false
        }
    }
}

private enum AppMetadata {
    static let name = "HealthLogiq"
    static let version = "1.0.0"
    static let releaseDate = "June 12, 2026"
    static let author = "Adib"
    static let dashboardActivityType = "com.smarthealth.dashboard"
    static let aboutActivityType = "com.smarthealth.about"
    static let keywords: Set<String> = [
        "HealthLogiq",
        "health metrics",
        "Apple Health",
        "Apple Intelligence",
        "activity",
        "heart rate",
        "recovery",
        "sleep",
        "HRV",
        "VO2 Max",
        "body battery",
        "strain"
    ]

    static var keywordText: String {
        keywords.sorted().joined(separator: ", ")
    }

    static func configureDashboardActivity(_ activity: NSUserActivity) {
        activity.title = "HealthLogiq Health Metrics"
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.keywords = keywords
        activity.userInfo = [
            "version": version,
            "category": "Health Metrics",
            "privacy": "On-device Apple Health insights"
        ]
    }

    static func configureAboutActivity(_ activity: NSUserActivity) {
        activity.title = "About HealthLogiq"
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.keywords = keywords.union(["about", "version", "privacy", "author"])
        activity.userInfo = [
            "version": version,
            "author": author,
            "releaseDate": releaseDate
        ]
    }
}

private struct MetricTile: View {
    enum Theme {
        case classic
        case colorful
    }

    let metric: HealthMetric
    let theme: Theme
    @State private var isTrendExplanationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: metric.systemImage)
                    .font(.title3)
                    .foregroundStyle(iconForegroundStyle)
                    .frame(width: 32, height: 32)
                    .background(iconBackgroundStyle, in: RoundedRectangle(cornerRadius: 8))

                Spacer()

                if let tileStatus {
                    SummaryStatusBadge(status: tileStatus, theme: theme)
                        .onTapGesture {
                            isTrendExplanationPresented = true
                        }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(metric.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(titleForegroundStyle)
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(metric.value)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(valueForegroundStyle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if !metric.unit.isEmpty {
                        Text(metric.unit)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(titleForegroundStyle)
                    }
                }
            }

            Text(metric.context)
                .font(.caption)
                .foregroundStyle(contextForegroundStyle)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
        .background(tileBackgroundStyle, in: RoundedRectangle(cornerRadius: 8))
        .alert(trendExplanationTitle, isPresented: $isTrendExplanationPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(trendExplanationMessage)
        }
    }

    private var iconForegroundStyle: Color {
        theme == .colorful ? .white : .accentColor
    }

    private var iconBackgroundStyle: Color {
        theme == .colorful ? .white.opacity(0.2) : Color.accentColor.opacity(0.12)
    }

    private var titleForegroundStyle: Color {
        theme == .colorful ? .white.opacity(0.82) : .secondary
    }

    private var valueForegroundStyle: Color {
        theme == .colorful ? .white : .primary
    }

    private var contextForegroundStyle: Color {
        theme == .colorful ? .white.opacity(0.78) : .secondary
    }

    private var tileBackgroundStyle: AnyShapeStyle {
        switch theme {
        case .classic:
            return AnyShapeStyle(Color(.systemBackground))
        case .colorful:
            return AnyShapeStyle(tileGradient)
        }
    }

    private var tileGradient: LinearGradient {
        LinearGradient(
            colors: tileColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var tileColors: [Color] {
        switch metric.title {
        case "Steps":
            return [Color(red: 0.20, green: 0.74, blue: 0.37), Color(red: 0.09, green: 0.55, blue: 0.25)]
        case "Active Energy":
            return [Color(red: 1.00, green: 0.25, blue: 0.26), Color(red: 0.84, green: 0.05, blue: 0.18)]
        case "Exercise":
            return [Color(red: 0.60, green: 0.86, blue: 0.15), Color(red: 0.22, green: 0.72, blue: 0.18)]
        case "Activity Heart Rate", "Resting HR":
            return [Color(red: 1.00, green: 0.18, blue: 0.37), Color(red: 0.76, green: 0.00, blue: 0.22)]
        case "HRV":
            return [Color(red: 0.35, green: 0.70, blue: 1.00), Color(red: 0.00, green: 0.42, blue: 0.86)]
        case "VO2 Max":
            return [Color(red: 0.00, green: 0.78, blue: 0.86), Color(red: 0.00, green: 0.48, blue: 0.76)]
        case "Sleep":
            return [Color(red: 0.38, green: 0.43, blue: 0.95), Color(red: 0.20, green: 0.22, blue: 0.62)]
        case "Body Battery":
            return [Color(red: 0.20, green: 0.78, blue: 0.74), Color(red: 0.00, green: 0.50, blue: 0.48)]
        case "Strain":
            return [Color(red: 1.00, green: 0.58, blue: 0.18), Color(red: 0.92, green: 0.22, blue: 0.08)]
        default:
            return [Color.accentColor, Color.accentColor.opacity(0.72)]
        }
    }

    private var tileStatus: MetricAverageStatus? {
        switch metric.trend {
        case .below:
            return .below
        case .near:
            return .near
        case .above:
            return .above
        case nil:
            return nil
        }
    }

    private var trendExplanationTitle: String {
        "\(metric.title) Trend"
    }

    private var trendExplanationMessage: String {
        guard let trend = metric.trend else {
            return "This tile does not have enough recent non-zero history to compare against your personal median yet."
        }

        let directionText: String
        switch trend {
        case .above:
            directionText = "positive"
        case .near:
            directionText = "stable"
        case .below:
            directionText = "negative"
        }

        return "This icon shows the trend for \(metric.title). Your current value is \(metric.valueText), compared with your recent personal median of \(formattedTrendReference(trend.referenceValue)). For this metric, \(betterDirectionText). That makes this a \(directionText) trend."
    }

    private var betterDirectionText: String {
        lowerIsBetter ? "a lower number is usually better" : "a higher number is usually better"
    }

    private var lowerIsBetter: Bool {
        ["Resting HR", "Strain"].contains(metric.title)
    }

    private func formattedTrendReference(_ value: Double) -> String {
        let number: String
        if value >= 100 || value.rounded() == value {
            number = value.formatted(.number.precision(.fractionLength(0)))
        } else {
            number = value.formatted(.number.precision(.fractionLength(1)))
        }
        return metric.unit.isEmpty ? number : "\(number) \(metric.unit)"
    }
}

private struct AboutAppView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.red)

                    Text(AppMetadata.name)
                        .font(.largeTitle.weight(.bold))

                    Text("A private health metrics companion that reads Apple Health data, visualizes trends, and helps interpret what changed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                aboutSection(title: "How It Works", systemImage: "waveform.path.ecg") {
                    Text("HealthLogiq requests read access to Apple Health metrics such as steps, exercise, activity heart rate, resting heart rate, HRV, VO2 Max, sleep, active energy, body battery, and strain.")
                    Text("The app summarizes the latest metrics into tiles and lets you open each metric for historical charts, medians, selected points, and baseline comparisons when profile data is available.")
                }

                aboutSection(title: "AI Advice", systemImage: "brain.head.profile") {
                    Text("On devices that support Apple Intelligence, HealthLogiq can use the on-device Foundation Models framework to answer chat questions using your current metrics and baseline context.")
                    Text("If Apple Intelligence is not available or not enabled, the app falls back to local rule-based insights. It should not be used as a diagnosis or a replacement for medical care.")
                }

                aboutSection(title: "Privacy", systemImage: "lock.shield") {
                    Text("Health values are read from Apple Health only after permission is granted. The app does not include network calls, API keys, analytics SDKs, or local health-data file storage.")
                    Text("Search metadata uses general app keywords only. It does not publish your health measurements or chat messages to Spotlight.")
                }

                aboutSection(title: "App Info", systemImage: "info.circle") {
                    labeledRow("Author", AppMetadata.author)
                    labeledRow("Version", AppMetadata.version)
                    labeledRow("Date", AppMetadata.releaseDate)
                    labeledText("Search Keywords", AppMetadata.keywordText)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("About The App")
        .navigationBarTitleDisplayMode(.inline)
        .userActivity(AppMetadata.aboutActivityType) { activity in
            AppMetadata.configureAboutActivity(activity)
        }
    }

    private func aboutSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                content()
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func labeledRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }

    private func labeledText(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension HealthMetric {
    var numericValue: Double? {
        Double(value.replacingOccurrences(of: ",", with: ""))
    }

    var valueText: String {
        unit.isEmpty ? value : "\(value) \(unit)"
    }
}

private enum BaselineMode: String, CaseIterable, Identifiable {
    case general = "General"
    case athletic = "Athletic"

    var id: String { rawValue }
}

private enum MetricChartStyle: String, CaseIterable, Identifiable {
    case line = "Line"
    case bar = "Bar"
    case area = "Area"

    var id: String { rawValue }
    var title: String { rawValue }

    var systemImage: String {
        switch self {
        case .line: return "chart.xyaxis.line"
        case .bar: return "chart.bar"
        case .area: return "chart.line.uptrend.xyaxis"
        }
    }
}

private enum MetricAverageStatus {
    case below
    case near
    case above

    var title: String {
        switch self {
        case .below: return "Negative trend"
        case .near: return "Near personal median"
        case .above: return "Positive trend"
        }
    }

    var systemImage: String {
        switch self {
        case .below: return "arrow.down"
        case .near: return "equal"
        case .above: return "arrow.up"
        }
    }

    var color: Color {
        switch self {
        case .below: return .orange
        case .near: return .secondary
        case .above: return .green
        }
    }
}

private struct MetricDetailView: View {
    let metric: HealthMetric
    let tileTheme: MetricTile.Theme

    @State private var selectedRange: HealthHistoryRange = .week
    @State private var chartStyle: MetricChartStyle = .line
    @State private var showsBaseline = true
    @State private var baselineMode: BaselineMode = .general
    @State private var showsMedian = true
    @State private var selectedSampleIndex = 0.0
    @State private var selectedChartDate: Date?
    @State private var samples: [HealthMetricSample] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let healthKitManager = HealthKitManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summarySection

                VStack(alignment: .leading, spacing: 10) {
                    Text("Time Window")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Time Window", selection: $selectedRange) {
                        ForEach(HealthHistoryRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Chart Type")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Chart Type", selection: $chartStyle) {
                        ForEach(MetricChartStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                chartSection
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedRange) {
            await loadHistory()
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Trend")
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if availableSamples.isEmpty && !isLoading {
                ContentUnavailableView("No Data", systemImage: "chart.xyaxis.line", description: Text("Apple Health has no available samples for this metric in the selected time window."))
                    .frame(minHeight: 220)
            } else {
                Chart {
                    ForEach(availableSamples) { sample in
                        switch chartStyle {
                        case .bar:
                            BarMark(
                                x: .value("Date", sample.date),
                                y: .value(metric.title, sample.value)
                            )
                            .foregroundStyle(chartColor)
                        case .line:
                            LineMark(
                                x: .value("Date", sample.date),
                                y: .value(metric.title, sample.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(chartColor)

                            if availableSamples.count <= 45 {
                                PointMark(
                                    x: .value("Date", sample.date),
                                    y: .value(metric.title, sample.value)
                                )
                                .symbolSize(26)
                                .foregroundStyle(chartColor)
                            }
                        case .area:
                            AreaMark(
                                x: .value("Date", sample.date),
                                y: .value(metric.title, sample.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(chartColor.opacity(0.26))

                            LineMark(
                                x: .value("Date", sample.date),
                                y: .value(metric.title, sample.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(chartColor)
                        }
                    }

                    if showsBaseline, let baseline = selectedBaselineReference {
                        RuleMark(y: .value("Baseline Low", baseline.lowerBound))
                            .foregroundStyle(baselineColor.opacity(0.78))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [7, 4]))
                            .annotation(
                                position: .trailing,
                                alignment: .trailing,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                            ) {
                                BaselineChartLabel(text: baseline.lowerLabel, color: baselineColor)
                                    .offset(x: -8)
                            }

                        if let upperBound = baseline.upperBound {
                            RuleMark(y: .value("Baseline High", upperBound))
                                .foregroundStyle(baselineColor.opacity(0.78))
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [7, 4]))
                                .annotation(
                                    position: .trailing,
                                    alignment: .trailing,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                                ) {
                                    BaselineChartLabel(text: baseline.upperLabel, color: baselineColor)
                                        .offset(x: -8)
                                }
                        }
                    }

                    if showsMedian, let medianValue {
                        RuleMark(y: .value("Median", medianValue))
                            .foregroundStyle(chartColor.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                            .annotation(
                                position: medianAnnotationPosition,
                                alignment: .center,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                            ) {
                                ChartAnnotationLabel(text: "Median \(formatted(medianValue))")
                            }
                    }

                    if let selectedSample {
                        RuleMark(x: .value("Selected Date", selectedSample.date))
                            .foregroundStyle(chartColor.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                        PointMark(
                            x: .value("Selected Date", selectedSample.date),
                            y: .value(metric.title, selectedSample.value)
                        )
                        .symbolSize(80)
                        .foregroundStyle(chartColor)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .chartXSelection(value: $selectedChartDate)
                .onChange(of: selectedChartDate) { _, newValue in
                    if let newValue {
                        selectNearestSample(to: newValue)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .padding(.horizontal, 8)
                        .padding(.vertical, 16)
                }
                .frame(height: 260)

                selectedSampleControl

                graphOptionsControl
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var graphOptionsControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasBaselineOption {
                Toggle("Show Baseline", isOn: $showsBaseline)
                    .font(.subheadline.weight(.medium))
                    .tint(chartColor)

                if showsBaseline {
                    Picker("Baseline Type", selection: $baselineMode) {
                        ForEach(BaselineMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Toggle("Show Median", isOn: $showsMedian)
                .font(.subheadline.weight(.medium))
                .tint(chartColor)
        }
        .padding(.top, 2)
    }

    private var selectedSampleControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected Point")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(selectedSampleDateText)
                        .font(.subheadline.weight(.medium))
                }

                Spacer()

                Text(selectedSampleValueText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(chartColor)
            }

            if availableSamples.count > 1 {
                Slider(
                    value: $selectedSampleIndex,
                    in: 0...Double(availableSamples.count - 1),
                    step: 1
                )
                .tint(chartColor)
            }
        }
        .padding(12)
        .background(chartColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(chartColor.opacity(0.18), lineWidth: 1)
        )
        .padding(.top, 4)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summary")
                .font(.headline)

            HStack(spacing: 12) {
                DetailStat(title: usesTotalSummary ? "Total" : "Average", value: primarySummary)
                DetailStat(title: "High", value: formatted(availableSamples.map(\.value).max()))
                DetailStat(title: "Low", value: formatted(availableSamples.map(\.value).min()))
            }

            HStack(spacing: 12) {
                DetailStat(title: "Median", value: formatted(medianValue))
                DetailStat(title: "Trend", value: trendSummary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var availableSamples: [HealthMetricSample] {
        samples.filter { $0.value.isFinite && $0.value > 0 }
    }

    private var selectedSample: HealthMetricSample? {
        guard !availableSamples.isEmpty else { return nil }
        let index = min(max(Int(selectedSampleIndex.rounded()), 0), availableSamples.count - 1)
        return availableSamples[index]
    }

    private var selectedSampleDateText: String {
        selectedSample?.date.formatted(.dateTime.month(.abbreviated).day().year()) ?? "--"
    }

    private var selectedSampleValueText: String {
        formatted(selectedSample?.value)
    }

    private func selectNearestSample(to date: Date) {
        guard !availableSamples.isEmpty else { return }

        let nearestIndex = availableSamples.indices.min { lhs, rhs in
            abs(availableSamples[lhs].date.timeIntervalSince(date)) < abs(availableSamples[rhs].date.timeIntervalSince(date))
        } ?? 0
        selectedSampleIndex = Double(nearestIndex)
    }

    private var primarySummary: String {
        guard !availableSamples.isEmpty else { return "--" }
        if usesTotalSummary {
            return formatted(availableSamples.reduce(0) { $0 + $1.value })
        }

        return formatted(averageValue)
    }

    private var averageValue: Double? {
        guard !availableSamples.isEmpty else { return nil }
        return availableSamples.reduce(0) { $0 + $1.value } / Double(availableSamples.count)
    }

    private var medianValue: Double? {
        let values = availableSamples.map(\.value).sorted()
        guard !values.isEmpty else { return nil }

        let midpoint = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[midpoint - 1] + values[midpoint]) / 2
        }
        return values[midpoint]
    }

    private var trendSummary: String {
        guard availableSamples.count >= 2,
              let first = availableSamples.first?.value,
              let last = availableSamples.last?.value else {
            return "--"
        }

        let delta = last - first
        let threshold = max(abs(first) * 0.03, 0.1)
        let direction: String
        if delta > threshold {
            direction = "Up"
        } else if delta < -threshold {
            direction = "Down"
        } else {
            direction = "Flat"
        }

        return "\(direction) \(formatted(abs(delta)))"
    }

    private var usesBars: Bool {
        ["Steps", "Active Energy", "Exercise", "Sleep", "Strain"].contains(metric.title)
    }

    private var usesTotalSummary: Bool {
        ["Steps", "Active Energy", "Exercise", "Sleep"].contains(metric.title)
    }

    private var medianAnnotationPosition: AnnotationPosition {
        chartStyle == .line ? .bottom : .top
    }

    private var hasBaselineOption: Bool {
        selectedBaselineReference != nil || metric.baselineReference != nil || athleticBaselineReference != nil
    }

    private var selectedBaselineReference: HealthMetricBaseline? {
        switch baselineMode {
        case .general:
            return metric.baselineReference
        case .athletic:
            return athleticBaselineReference ?? metric.baselineReference
        }
    }

    private var athleticBaselineReference: HealthMetricBaseline? {
        switch metric.title {
        case "Resting HR":
            return HealthMetricBaseline(
                lowerBound: 40,
                upperBound: 60,
                label: "Athletic baseline",
                source: "Athletic resting heart rates commonly run lower than the general adult range"
            )
        case "Activity Heart Rate":
            guard let general = metric.baselineReference, let upperBound = general.upperBound else { return nil }
            return HealthMetricBaseline(
                lowerBound: general.lowerBound * 0.85,
                upperBound: upperBound * 0.95,
                label: "Athletic target zone",
                source: "Athletic comparison adjusted lower from the age-based general target zone"
            )
        case "VO2 Max":
            guard let general = metric.baselineReference else { return nil }
            return HealthMetricBaseline(
                lowerBound: general.lowerBound * 1.18,
                upperBound: nil,
                label: "Athletic baseline",
                source: "Athletic comparison set above the age- and sex-adjusted good VO2 Max reference"
            )
        case "Sleep":
            return metric.baselineReference
        default:
            return nil
        }
    }

    private var baselineColor: Color {
        Color(red: 0.58, green: 0.32, blue: 0.90)
    }

    private var chartColor: Color {
        switch metric.title {
        case "Steps": return Color(red: 0.20, green: 0.74, blue: 0.37)
        case "Active Energy", "Activity Heart Rate", "Resting HR": return Color(red: 1.00, green: 0.18, blue: 0.37)
        case "Exercise": return Color(red: 0.55, green: 0.82, blue: 0.14)
        case "HRV": return Color(red: 0.00, green: 0.42, blue: 0.86)
        case "VO2 Max": return Color(red: 0.00, green: 0.60, blue: 0.78)
        case "Sleep": return Color(red: 0.38, green: 0.43, blue: 0.95)
        case "Body Battery": return Color(red: 0.00, green: 0.58, blue: 0.54)
        case "Strain": return Color(red: 0.92, green: 0.32, blue: 0.08)
        default: return .accentColor
        }
    }

    private func loadHistory() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let history = try await healthKitManager.fetchHistory(for: metric, range: selectedRange)
            samples = history
            let availableHistory = history.filter { $0.value.isFinite }
            selectedSampleIndex = Double(max(availableHistory.count - 1, 0))
            selectedChartDate = availableHistory.last?.date
        } catch {
            samples = []
            selectedSampleIndex = 0
            selectedChartDate = nil
            errorMessage = error.localizedDescription
        }
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "--" }
        let number: String
        if value >= 100 || value.rounded() == value {
            number = value.formatted(.number.precision(.fractionLength(0)))
        } else {
            number = value.formatted(.number.precision(.fractionLength(1)))
        }

        return metric.unit.isEmpty ? number : "\(number) \(metric.unit)"
    }
}

private extension HealthMetricBaseline {
    var lowerLabel: String {
        if isRange {
            return "Low \(formattedBaselineValue(lowerBound))"
        }
        return ">= \(formattedBaselineValue(lowerBound))"
    }

    var upperLabel: String {
        guard let upperBound else { return "" }
        return "High \(formattedBaselineValue(upperBound))"
    }

    private func formattedBaselineValue(_ value: Double) -> String {
        if value >= 100 || value.rounded() == value {
            return value.formatted(.number.precision(.fractionLength(0)))
        }
        return value.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct BaselineChartLabel: View {
    let text: String
    let color: Color

    var body: some View {
        ChartAnnotationLabel(text: text, color: color, maxWidth: 92)
    }
}

private struct ChartAnnotationLabel: View {
    let text: String
    var color: Color = .primary
    var maxWidth: CGFloat = 118

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(Color(.systemBackground).opacity(0.72), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.24), lineWidth: 1)
            )
            .allowsHitTesting(false)
    }
}

private struct SummaryStatusBadge: View {
    let status: MetricAverageStatus
    var theme: MetricTile.Theme = .classic

    var body: some View {
        Image(systemName: status.systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(foregroundColor)
            .frame(width: 26, height: 26)
            .background(backgroundColor, in: Circle())
            .accessibilityLabel(status.title)
    }

    private var foregroundColor: Color {
        theme == .colorful ? .white : status.color
    }

    private var backgroundColor: Color {
        theme == .colorful ? .white.opacity(0.22) : status.color.opacity(0.12)
    }
}

private struct DetailStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user {
                Spacer(minLength: 44)
            }

            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)

            if message.role == .assistant {
                Spacer(minLength: 44)
            }
        }
        .padding(.horizontal, 14)
    }

    private var backgroundStyle: Color {
        switch message.role {
        case .assistant:
            return Color(.secondarySystemGroupedBackground)
        case .user:
            return Color.accentColor
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
