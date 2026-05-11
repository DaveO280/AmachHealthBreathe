import SwiftUI
import AmachBreatheShared

struct HistoryView: View {

    @EnvironmentObject private var sessionService: SessionService
    @State private var rowPendingDeletion: SessionHistoryModel.Row?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.amachBg.ignoresSafeArea()
                VStack(spacing: 0) {
                    headerSection
                        .padding(.horizontal, AmachSpacing.md)
                        .padding(.top, AmachSpacing.sm)
                    WalletStatusBanner()
                    let rows = SessionHistoryModel.rows(from: sessions)
                    if rows.isEmpty {
                        AmachEmptyState(
                            icon: AmachIcon.breathe,
                            title: "No sessions yet",
                            message: "Complete a breathing session on your Apple Watch or iPhone to see your history here."
                        )
                    } else {
                        ScrollView {
                            LazyVStack(spacing: AmachSpacing.cardGap) {
                                ForEach(rows) { row in
                                    NavigationLink(value: row) {
                                        SessionRowView(row: row)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Delete Session", role: .destructive) {
                                            rowPendingDeletion = row
                                        }
                                    }
                                }
                            }
                            .padding(AmachSpacing.screenEdge)
                            .padding(.bottom, AmachSpacing.xxl)
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SessionHistoryModel.Row.self) { row in
                SessionDetailView(row: row)
            }
            .confirmationDialog(
                "Delete session?",
                isPresented: Binding(
                    get: { rowPendingDeletion != nil },
                    set: { if !$0 { rowPendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: rowPendingDeletion
            ) { row in
                Button("Delete Session", role: .destructive) {
                    sessionService.deleteSession(id: row.id)
                    rowPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { rowPendingDeletion = nil }
            } message: { _ in
                Text("This removes the saved session from this device.")
            }
        }
    }

    private var sessions: [BreathingSessionRecord] {
        sessionService.sessions.map(\.breathingSession)
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: AmachSpacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                AmachBrandMark(layout: .compact)
                Text("History")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.amachTextPrimary)
            }
            Spacer()
        }
        .padding(.bottom, AmachSpacing.sm)
    }
}

// MARK: - Row cell

private struct SessionRowView: View {
    let row: SessionHistoryModel.Row

    var body: some View {
        HStack(spacing: AmachSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: AmachSpacing.xs) {
                    Text(row.dateLabel)
                        .font(AmachType.h3)
                        .foregroundStyle(Color.amachTextPrimary)
                    if row.isPhoneSession {
                        Image(systemName: "iphone")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.amachTextTertiary)
                    }
                }
                Text("\(row.durationLabel) · \(row.bpm, specifier: "%.1f") BPM · \(row.ratio)")
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                coherenceBadge
                if !row.isPhoneSession && row.avgHRV > 0 {
                    Text("\(Int(row.avgHRV)) ms HRV")
                        .font(AmachType.tiny)
                        .foregroundStyle(Color.amachTextSecondary)
                }
            }
        }
        .padding(AmachSpacing.md)
        .amachCard()
    }

    @ViewBuilder
    private var coherenceBadge: some View {
        if row.isPhoneSession {
            Text("—")
                .font(AmachType.tiny)
                .fontWeight(.semibold)
                .foregroundStyle(Color.amachTextTertiary)
                .padding(.horizontal, AmachSpacing.sm)
                .padding(.vertical, 2)
                .background(Color.amachTextTertiary.opacity(0.10))
                .clipShape(Capsule())
        } else {
            Text("\(row.coherencePercent)%")
                .font(AmachType.tiny)
                .fontWeight(.semibold)
                .foregroundStyle(coherenceColor)
                .padding(.horizontal, AmachSpacing.sm)
                .padding(.vertical, 2)
                .background(coherenceColor.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private var coherenceColor: Color {
        switch row.coherencePercent {
        case 70...100: return .amachPrimary
        case 40..<70:  return Color.amachWarning
        default:       return Color.amachDestructive
        }
    }
}

extension SessionHistoryModel.Row: @retroactive Hashable {
    public static func == (lhs: SessionHistoryModel.Row, rhs: SessionHistoryModel.Row) -> Bool {
        lhs.id == rhs.id
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
