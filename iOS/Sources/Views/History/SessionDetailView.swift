import SwiftUI
import Charts
import AmachBreatheShared

struct SessionDetailView: View {

    let row: SessionHistoryModel.Row

    @EnvironmentObject private var sessionService: SessionService

    var body: some View {
        ZStack {
            Color.amachBg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: AmachSpacing.sectionSpacing) {
                    summaryCard
                    if !hrvPoints.isEmpty { hrvChart }
                    coherenceSection
                    if let rating = row.reflectionRating { reflectionCard(rating) }
                }
                .padding(AmachSpacing.screenEdge)
                .padding(.bottom, AmachSpacing.xxl)
            }
        }
        .navigationTitle(row.dateLabel)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Data

    private var record: BreathingSessionRecord? {
        sessionService.sessions.first { $0.id == row.id }?.breathingSession
    }

    // Synthetic HRV arc from baseline → peak → recovery using available data
    private var hrvPoints: [(label: String, value: Double)] {
        guard let r = record else { return [] }
        var pts: [(String, Double)] = []
        if r.baselineHRV > 0 { pts.append(("Baseline", r.baselineHRV)) }
        if r.avgHRV > 0      { pts.append(("Session", r.avgHRV)) }
        if r.recoveryHRV > 0 { pts.append(("Recovery", r.recoveryHRV)) }
        return pts
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(spacing: AmachSpacing.md) {
            HStack(spacing: 0) {
                metricTile(value: row.durationLabel, label: "Duration")
                Divider().frame(height: 40)
                metricTile(value: String(format: "%.1f BPM", row.bpm), label: "Breath Rate")
                Divider().frame(height: 40)
                metricTile(value: row.ratio, label: "Ratio")
            }
        }
        .padding(AmachSpacing.cardPadding)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
    }

    private func metricTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AmachType.h3)
                .foregroundStyle(Color.amachTextPrimary)
            Text(label)
                .font(AmachType.tiny)
                .foregroundStyle(Color.amachTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - HRV chart

    private var hrvChart: some View {
        VStack(alignment: .leading, spacing: AmachSpacing.sm) {
            Text("HRV")
                .font(AmachType.h3)
                .foregroundStyle(Color.amachTextPrimary)
            Chart {
                ForEach(Array(hrvPoints.enumerated()), id: \.offset) { idx, pt in
                    LineMark(
                        x: .value("Phase", pt.label),
                        y: .value("HRV (ms)", pt.value)
                    )
                    .foregroundStyle(Color.amachPrimary)
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Phase", pt.label),
                        y: .value("HRV (ms)", pt.value)
                    )
                    .foregroundStyle(Color.amachPrimary)
                    .symbolSize(60)
                }
            }
            .frame(height: 140)
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        Text(value.as(String.self) ?? "")
                            .font(AmachType.tiny)
                            .foregroundStyle(Color.amachTextSecondary)
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        Text("\(value.as(Double.self).map { Int($0) } ?? 0) ms")
                            .font(AmachType.tiny)
                            .foregroundStyle(Color.amachTextSecondary)
                    }
                    AxisGridLine().foregroundStyle(Color.amachTextTertiary.opacity(0.2))
                }
            }
        }
        .padding(AmachSpacing.cardPadding)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
    }

    // MARK: - Coherence

    private var coherenceSection: some View {
        VStack(alignment: .leading, spacing: AmachSpacing.md) {
            Text("Coherence")
                .font(AmachType.h3)
                .foregroundStyle(Color.amachTextPrimary)
            HStack(spacing: AmachSpacing.lg) {
                ZStack {
                    Circle()
                        .stroke(Color.amachTextTertiary.opacity(0.2), lineWidth: 10)
                        .frame(width: 80, height: 80)
                    Circle()
                        .trim(from: 0, to: row.coherenceScore)
                        .stroke(coherenceRingColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                    Text("\(row.coherencePercent)%")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.amachTextPrimary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(coherenceLabel)
                        .font(AmachType.body)
                        .foregroundStyle(Color.amachTextPrimary)
                    Text(coherenceSubtitle)
                        .font(AmachType.caption)
                        .foregroundStyle(Color.amachTextSecondary)
                }
                Spacer()
            }
        }
        .padding(AmachSpacing.cardPadding)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
    }

    private var coherenceRingColor: Color {
        switch row.coherencePercent {
        case 70...100: return .amachPrimary
        case 40..<70:  return Color.amachWarning
        default:       return Color.amachDestructive
        }
    }

    private var coherenceLabel: String {
        switch row.coherencePercent {
        case 70...100: return "High Coherence"
        case 40..<70:  return "Moderate Coherence"
        default:       return "Low Coherence"
        }
    }

    private var coherenceSubtitle: String {
        switch row.coherencePercent {
        case 70...100: return "Heart rhythm synchronized with breath"
        case 40..<70:  return "Partial synchronization achieved"
        default:       return "Keep practicing to build coherence"
        }
    }

    // MARK: - Reflection

    private func reflectionCard(_ rating: Int) -> some View {
        VStack(alignment: .leading, spacing: AmachSpacing.md) {
            Text("How you felt")
                .font(AmachType.h3)
                .foregroundStyle(Color.amachTextPrimary)
            HStack(spacing: AmachSpacing.sm) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .foregroundStyle(star <= rating ? Color.amachGold : Color.amachTextTertiary)
                        .font(.system(size: 24))
                }
            }
        }
        .padding(AmachSpacing.cardPadding)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
    }
}
