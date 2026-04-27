import SwiftUI
import Charts
import AmachBreatheShared

struct TrendView: View {

    @EnvironmentObject private var sessionService: SessionService

    private enum Window: String, CaseIterable {
        case week  = "7D"
        case month = "30D"
        case all   = "All"
    }

    @State private var selectedWindow: Window = .month

    var body: some View {
        NavigationStack {
            ZStack {
                Color.amachBg.ignoresSafeArea()
                if allSessions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: AmachSpacing.sectionSpacing) {
                            windowPicker
                            consistencySection
                            hrvTrendSection
                            coherenceTrendSection
                        }
                        .padding(AmachSpacing.screenEdge)
                        .padding(.bottom, AmachSpacing.xxl)
                    }
                }
            }
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var emptyState: some View {
        VStack(spacing: AmachSpacing.lg) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(Color.amachTextTertiary)
            Text("No data yet")
                .font(AmachType.h2)
                .foregroundStyle(Color.amachTextPrimary)
            Text("Complete at least 3 sessions to see trends, streaks, and HRV progress.")
                .font(AmachType.caption)
                .foregroundStyle(Color.amachTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AmachSpacing.xl)
        }
    }

    // MARK: - Filtered data

    private var allSessions: [BreathingSessionRecord] {
        sessionService.sessions.map(\.breathingSession)
    }

    private var filteredSessions: [BreathingSessionRecord] {
        let now = Date()
        switch selectedWindow {
        case .week:
            let cutoff = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: now))!
            return allSessions.filter { $0.timestamp >= cutoff }
        case .month:
            let cutoff = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: now))!
            return allSessions.filter { $0.timestamp >= cutoff }
        case .all:
            return allSessions
        }
    }

    // MARK: - Window picker

    private var windowPicker: some View {
        HStack(spacing: 0) {
            ForEach(Window.allCases, id: \.self) { window in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedWindow = window }
                } label: {
                    Text(window.rawValue)
                        .font(AmachType.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AmachSpacing.sm)
                        .background(selectedWindow == window ? Color.amachPrimary : Color.clear)
                        .foregroundStyle(selectedWindow == window ? .white : Color.amachTextSecondary)
                }
            }
        }
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Consistency

    private var consistencySection: some View {
        let stats = TrendEngine.consistencyStats(sessions: allSessions)
        return VStack(alignment: .leading, spacing: AmachSpacing.md) {
            Text("Practice")
                .font(AmachType.h3)
                .foregroundStyle(Color.amachTextPrimary)
            HStack(spacing: 0) {
                consistencyTile(value: "\(stats.currentStreak)", label: "Streak", unit: "days")
                Divider().frame(height: 40)
                consistencyTile(value: "\(stats.last7Days)", label: "This week", unit: "sessions")
                Divider().frame(height: 40)
                consistencyTile(value: "\(stats.totalSessions)", label: "All time", unit: "sessions")
            }
        }
        .padding(AmachSpacing.cardPadding)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func consistencyTile(value: String, label: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.amachPrimary)
            Text(label)
                .font(AmachType.tiny)
                .foregroundStyle(Color.amachTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - HRV trend

    private var hrvTrendSection: some View {
        let points = TrendEngine.dailyHRVTrend(sessions: filteredSessions)
        return VStack(alignment: .leading, spacing: AmachSpacing.sm) {
            Text("HRV Trend")
                .font(AmachType.h3)
                .foregroundStyle(Color.amachTextPrimary)
            if points.isEmpty {
                emptyChartPlaceholder("No HRV data in this window")
            } else {
                Chart {
                    ForEach(points, id: \.date) { pt in
                        LineMark(
                            x: .value("Date", pt.date),
                            y: .value("HRV (ms)", pt.averageHRV)
                        )
                        .foregroundStyle(Color.amachPrimary)
                        .interpolationMethod(.catmullRom)
                        AreaMark(
                            x: .value("Date", pt.date),
                            y: .value("HRV (ms)", pt.averageHRV)
                        )
                        .foregroundStyle(Color.amachPrimary.opacity(0.1))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .frame(height: 160)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(AmachType.tiny)
                        AxisGridLine().foregroundStyle(Color.amachTextTertiary.opacity(0.15))
                    }
                }
                .chartYAxis {
                    AxisMarks { val in
                        AxisValueLabel {
                            Text("\(val.as(Double.self).map { Int($0) } ?? 0)")
                                .font(AmachType.tiny)
                                .foregroundStyle(Color.amachTextSecondary)
                        }
                        AxisGridLine().foregroundStyle(Color.amachTextTertiary.opacity(0.15))
                    }
                }
            }
        }
        .padding(AmachSpacing.cardPadding)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Coherence trend

    private var coherenceTrendSection: some View {
        let points = TrendEngine.coherenceTrend(sessions: filteredSessions)
        return VStack(alignment: .leading, spacing: AmachSpacing.sm) {
            Text("Coherence")
                .font(AmachType.h3)
                .foregroundStyle(Color.amachTextPrimary)
            if points.isEmpty {
                emptyChartPlaceholder("No sessions in this window")
            } else {
                Chart {
                    ForEach(points, id: \.sessionId) { pt in
                        PointMark(
                            x: .value("Date", pt.date),
                            y: .value("Coherence", pt.coherenceScore * 100)
                        )
                        .foregroundStyle(Color.amachPrimary)
                        .symbolSize(40)
                        LineMark(
                            x: .value("Date", pt.date),
                            y: .value("Coherence", pt.coherenceScore * 100)
                        )
                        .foregroundStyle(Color.amachPrimary.opacity(0.4))
                        .interpolationMethod(.catmullRom)
                    }
                    RuleMark(y: .value("Target", 70))
                        .foregroundStyle(Color(hex: "10B981").opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                .frame(height: 160)
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(AmachType.tiny)
                        AxisGridLine().foregroundStyle(Color.amachTextTertiary.opacity(0.15))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { val in
                        AxisValueLabel {
                            Text("\(val.as(Double.self).map { Int($0) } ?? 0)%")
                                .font(AmachType.tiny)
                                .foregroundStyle(Color.amachTextSecondary)
                        }
                        AxisGridLine().foregroundStyle(Color.amachTextTertiary.opacity(0.15))
                    }
                }
            }
        }
        .padding(AmachSpacing.cardPadding)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func emptyChartPlaceholder(_ message: String) -> some View {
        Text(message)
            .font(AmachType.caption)
            .foregroundStyle(Color.amachTextTertiary)
            .frame(height: 120)
            .frame(maxWidth: .infinity)
    }
}
