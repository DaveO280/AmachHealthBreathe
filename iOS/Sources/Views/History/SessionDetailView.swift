import SwiftUI
import Charts
import AmachBreatheShared

struct SessionDetailView: View {

    let row: SessionHistoryModel.Row

    @EnvironmentObject private var sessionService: SessionService
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            Color.amachBg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: AmachSpacing.sectionSpacing) {
                    summaryCard
                    if !hrvPoints.isEmpty { hrvChart }
                    coherenceSection
                    if let metrics = record?.audioBreathMetrics { audioBreathCard(metrics) }
                    if let record {
                        CoachConversationView(record: record, style: .card)
                    }
                    if let rating = row.reflectionRating { reflectionCard(rating) }
                }
                .padding(AmachSpacing.screenEdge)
                .padding(.bottom, AmachSpacing.xxl)
            }
        }
        .navigationTitle(row.dateLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete session")
            }
        }
        .confirmationDialog("Delete session?",
                            isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Delete Session", role: .destructive) {
                sessionService.deleteSession(id: row.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the saved session from this device.")
        }
    }

    // MARK: - Data

    private var record: BreathingSessionRecord? {
        sessionService.sessions.first { $0.id == row.id }?.breathingSession
    }

    // Synthetic HRV arc from baseline → peak → recovery using available data
    private var hrvPoints: [(label: String, value: Double)] {
        guard let r = record else { return [] }
        var pts: [(String, Double)] = []
        if let v = r.baselineHRV, v > 0 { pts.append(("Baseline", v)) }
        if let v = r.avgHRV, v > 0 { pts.append(("Session", v)) }
        if let v = r.recoveryHRV, v > 0 { pts.append(("Recovery", v)) }
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
                ForEach(Array(hrvPoints.enumerated()), id: \.offset) { _, pt in
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
            if row.isPhoneSession {
                HStack(spacing: AmachSpacing.sm) {
                    Image(systemName: "iphone")
                        .foregroundStyle(Color.amachTextTertiary)
                    Text("HRV tracking requires Apple Watch")
                        .font(AmachType.caption)
                        .foregroundStyle(Color.amachTextSecondary)
                }
            } else {
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

    private func audioBreathCard(_ metrics: AudioBreathMetrics) -> some View {
        VStack(alignment: .leading, spacing: AmachSpacing.md) {
            HStack {
                Text("Audio Breath Tracking")
                    .font(AmachType.h3)
                    .foregroundStyle(Color.amachTextPrimary)
                Spacer()
                Text(metrics.dataQuality.rawValue.capitalized)
                    .font(AmachType.tiny.weight(.semibold))
                    .foregroundStyle(audioQualityColor(metrics.dataQuality))
                    .padding(.horizontal, AmachSpacing.sm)
                    .padding(.vertical, 2)
                    .background(audioQualityColor(metrics.dataQuality).opacity(0.12))
                    .clipShape(Capsule())
            }

            if metrics.permissionGranted, let estimated = metrics.estimatedBreathingBPM {
                HStack(spacing: 0) {
                    metricTile(value: String(format: "%.1f BPM", estimated), label: "Estimated")
                    Divider().frame(height: 40)
                    metricTile(value: String(format: "%.0f%%", (metrics.adherenceScore ?? 0) * 100), label: "Timing Match")
                    Divider().frame(height: 40)
                    metricTile(value: String(format: "%.0fs", metrics.analyzedDurationSeconds), label: "Analyzed")
                }
                Text("Experimental estimate from on-device microphone amplitude. Raw audio is not stored.")
                    .font(AmachType.tiny)
                    .foregroundStyle(Color.amachTextTertiary)
            } else {
                Text("Audio tracking was enabled, but no usable microphone estimate was captured.")
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
            }
        }
        .padding(AmachSpacing.cardPadding)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.card))
    }

    private func audioQualityColor(_ quality: AudioBreathDataQuality) -> Color {
        switch quality {
        case .good: return Color.amachPrimary
        case .fair: return Color.amachWarning
        case .low, .unavailable: return Color.amachTextTertiary
        }
    }
}
