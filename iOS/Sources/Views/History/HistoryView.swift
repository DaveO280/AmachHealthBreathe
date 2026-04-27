import SwiftUI
import AmachBreatheShared

struct HistoryView: View {

    @EnvironmentObject private var sessionService: SessionService

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WalletStatusBanner()
                ZStack {
                    Color.amachBg.ignoresSafeArea()
                    let rows = SessionHistoryModel.rows(from: sessions)
                    if rows.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: AmachSpacing.cardGap) {
                                ForEach(rows) { row in
                                    NavigationLink(value: row) {
                                        SessionRowView(row: row)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(AmachSpacing.screenEdge)
                            .padding(.bottom, AmachSpacing.xxl)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: SessionHistoryModel.Row.self) { row in
                SessionDetailView(row: row)
            }
        }
    }

    private var sessions: [BreathingSessionRecord] {
        sessionService.sessions.map(\.breathingSession)
    }

    private var emptyState: some View {
        VStack(spacing: AmachSpacing.lg) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: AmachType.iconHero))
                .foregroundStyle(Color.amachTextTertiary)
            Text("No sessions yet")
                .font(AmachType.h2)
                .foregroundStyle(Color.amachTextPrimary)
            Text("Complete a breathing session on your Apple Watch to see your history here.")
                .font(AmachType.caption)
                .foregroundStyle(Color.amachTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AmachSpacing.xl)
        }
    }
}

// MARK: - Row cell

private struct SessionRowView: View {
    let row: SessionHistoryModel.Row

    var body: some View {
        HStack(spacing: AmachSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.dateLabel)
                    .font(AmachType.h3)
                    .foregroundStyle(Color.amachTextPrimary)
                Text("\(row.durationLabel) · \(row.bpm, specifier: "%.1f") BPM · \(row.ratio)")
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                coherenceBadge
                if row.avgHRV > 0 {
                    Text("\(Int(row.avgHRV)) ms HRV")
                        .font(AmachType.tiny)
                        .foregroundStyle(Color.amachTextSecondary)
                }
            }
        }
        .padding(AmachSpacing.md)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
    }

    private var coherenceBadge: some View {
        Text("\(row.coherencePercent)%")
            .font(AmachType.tiny)
            .fontWeight(.semibold)
            .foregroundStyle(coherenceColor)
            .padding(.horizontal, AmachSpacing.sm)
            .padding(.vertical, 2)
            .background(coherenceColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var coherenceColor: Color {
        switch row.coherencePercent {
        case 70...100: return .amachPrimary
        case 40..<70:  return Color.amachWarning
        default:       return Color.amachDestructive
        }
    }
}

extension SessionHistoryModel.Row: Hashable {
    public static func == (lhs: SessionHistoryModel.Row, rhs: SessionHistoryModel.Row) -> Bool {
        lhs.id == rhs.id
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
