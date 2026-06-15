import SwiftUI
import AmachBreatheShared

struct SettingsView: View {

    @EnvironmentObject private var settingsService: AppSettingsService
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var sessionService: SessionService
    @EnvironmentObject private var watchConnectivity: WatchConnectivityService

    @State private var showManageSubscription = false
    @State private var showAddReminder = false
    @State private var pendingReminderTime = Date()
    @State private var showIssueReportSheet = false
    @State private var issueReportURL: URL?
    @State private var issueReportError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.amachBg.ignoresSafeArea()
                VStack(spacing: 0) {
                    headerSection
                        .padding(.horizontal, AmachSpacing.md)
                        .padding(.top, AmachSpacing.sm)
                    ScrollView {
                        VStack(spacing: AmachSpacing.sectionSpacing) {
                            subscriptionSection
                            breathingSection
                            reminderSection
                            audioSection
                            pacerSection
                            supportSection
                        }
                        .padding(AmachSpacing.screenEdge)
                        .padding(.bottom, AmachSpacing.xxl)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showManageSubscription) {
                SubscriptionManagementView()
                    .environmentObject(subscriptionService)
            }
            .sheet(isPresented: $showIssueReportSheet) {
                if let issueReportURL {
                    ShareSheet(items: [issueReportURL])
                }
            }
            .alert("Could Not Create Report", isPresented: Binding(
                get: { issueReportError != nil },
                set: { if !$0 { issueReportError = nil } }
            )) {
                Button("OK", role: .cancel) { issueReportError = nil }
            } message: {
                Text(issueReportError ?? "Please try again.")
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: AmachSpacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                AmachBrandMark(layout: .compact)
                Text("Settings")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.amachTextPrimary)
            }
            Spacer()
        }
        .padding(.bottom, AmachSpacing.sm)
    }

    // MARK: - Sections

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: AmachSpacing.sm) {
            sectionHeader("Subscription")
            Button {
                showManageSubscription = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(subscriptionTierLabel)
                            .font(AmachType.body)
                            .foregroundStyle(Color.amachTextPrimary)
                        Text(subscriptionTierDetail)
                            .font(AmachType.caption)
                            .foregroundStyle(Color.amachTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.amachTextTertiary)
                }
                .padding(AmachSpacing.md)
            }
            .amachCard()
        }
    }

    private var subscriptionTierLabel: String {
        switch subscriptionService.state {
        case .trial:      return "Free Trial"
        case .subscribed: return "Subscribed"
        case .connected:  return "Connected — Free"
        case .expired:    return "Trial Ended"
        }
    }

    private var subscriptionTierDetail: String {
        switch subscriptionService.state {
        case .trial:      return "Sync sessions or subscribe after trial"
        case .subscribed: return "$4.99/month · Manage in App Store"
        case .connected:  return "3+ sessions/month keeps access free"
        case .expired:    return "Subscribe or sync to regain access"
        }
    }

    // MARK: - Reminders

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: AmachSpacing.sm) {
            sectionHeader("Reminders")
            VStack(spacing: 0) {
                let reminders = settingsService.settings.reminderSecondsFromMidnight

                if reminders.isEmpty {
                    HStack {
                        Text("No reminders set")
                            .font(AmachType.body)
                            .foregroundStyle(Color.amachTextSecondary)
                        Spacer()
                    }
                    .padding(AmachSpacing.md)
                } else {
                    ForEach(Array(reminders.enumerated()), id: \.offset) { index, seconds in
                        HStack {
                            Text(NotificationScheduler.displayTime(secondsFromMidnight: seconds))
                                .font(AmachType.body)
                                .foregroundStyle(Color.amachTextPrimary)
                            Spacer()
                            Button {
                                removeReminder(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(Color.amachDestructive)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(AmachSpacing.md)
                        if index < reminders.count - 1 {
                            Divider().padding(.leading, AmachSpacing.md)
                        }
                    }
                }

                if reminders.count < NotificationScheduler.maxRemindersPerDay {
                    Divider().padding(.leading, AmachSpacing.md)
                    Button {
                        pendingReminderTime = Date()
                        showAddReminder = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.amachPrimary)
                            Text("Add Reminder")
                                .font(AmachType.body)
                                .foregroundStyle(Color.amachPrimary)
                        }
                        .padding(AmachSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .background(Color.amachSurface)
            .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))

            Text("Daily breathing reminders. Max \(NotificationScheduler.maxRemindersPerDay) per day.")
                .font(AmachType.tiny)
                .foregroundStyle(Color.amachTextTertiary)
                .padding(.horizontal, AmachSpacing.xs)
        }
        .sheet(isPresented: $showAddReminder) {
            addReminderSheet
        }
    }

    private var addReminderSheet: some View {
        NavigationStack {
            ZStack {
                Color.amachBg.ignoresSafeArea()
                DatePicker(
                    "Reminder Time",
                    selection: $pendingReminderTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding()
            }
            .navigationTitle("Add Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showAddReminder = false }
                        .foregroundStyle(Color.amachTextSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        addReminder()
                        showAddReminder = false
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.amachPrimary)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func addReminder() {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: pendingReminderTime)
        let seconds = (comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60
        var updated = settingsService.settings.reminderSecondsFromMidnight
        guard !updated.contains(seconds) else { return }
        updated.append(seconds)
        settingsService.updateReminders(updated)
        Task { await NotificationService.shared.scheduleReminders(updated) }
    }

    private func removeReminder(at index: Int) {
        var updated = settingsService.settings.reminderSecondsFromMidnight
        guard index < updated.count else { return }
        updated.remove(at: index)
        settingsService.updateReminders(updated)
        Task { await NotificationService.shared.scheduleReminders(updated) }
    }

    private var breathingSection: some View {
        VStack(alignment: .leading, spacing: AmachSpacing.sm) {
            sectionHeader("Breathing")
            VStack(spacing: 0) {
                settingsRow("Default Ratio") {
                    Picker("Ratio", selection: Binding(
                        get: { settingsService.settings.defaultRatio },
                        set: { settingsService.updateRatio($0) }
                    )) {
                        ForEach(BreathRatio.allCases, id: \.self) { ratio in
                            Text(ratio.displayLabel).tag(ratio)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
                Divider().padding(.leading, AmachSpacing.md)
                Toggle(isOn: Binding(
                    get: { settingsService.settings.watchCompanionAudioTrackingEnabled },
                    set: { settingsService.updateWatchCompanionAudioTracking($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iPhone mic during Watch sessions")
                            .font(AmachType.body)
                            .foregroundStyle(Color.amachTextPrimary)
                        Text("Phone nearby and unlocked in a quiet room.")
                            .font(AmachType.caption)
                            .foregroundStyle(Color.amachTextSecondary)
                    }
                }
                .padding(AmachSpacing.md)
            }
            .amachCard()
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: AmachSpacing.sm) {
            sectionHeader("Audio")
            VStack(spacing: 0) {
                settingsRow("Volume") {
                    Slider(
                        value: Binding(
                            get: { settingsService.settings.audioVolume },
                            set: { settingsService.updateVolume($0) }
                        ),
                        in: 0...1
                    )
                    .accentColor(Color.amachPrimary)
                    .frame(width: 140)
                }
            }
            .amachCard()
        }
    }

    private var pacerSection: some View {
        VStack(alignment: .leading, spacing: AmachSpacing.sm) {
            sectionHeader("Pacer Style")
            VStack(spacing: 0) {
                ForEach(AppSettings.PacerStyle.allCases, id: \.self) { style in
                    let isSelected = settingsService.settings.pacerStyle == style
                    Button {
                        settingsService.updatePacerStyle(style)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.displayName)
                                    .font(AmachType.body)
                                    .foregroundStyle(Color.amachTextPrimary)
                                Text(style.description)
                                    .font(AmachType.caption)
                                    .foregroundStyle(Color.amachTextSecondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.amachPrimary)
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding(AmachSpacing.md)
                    }
                    if style != AppSettings.PacerStyle.allCases.last {
                        Divider().padding(.leading, AmachSpacing.md)
                    }
                }
            }
            .amachCard()
        }
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: AmachSpacing.sm) {
            sectionHeader("Support")
            Button {
                createIssueReport()
            } label: {
                HStack(spacing: AmachSpacing.md) {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.amachPrimary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Report Issue")
                            .font(AmachType.body)
                            .foregroundStyle(Color.amachTextPrimary)
                        Text("Share app, watch, session, and diagnostic context.")
                            .font(AmachType.caption)
                            .foregroundStyle(Color.amachTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.amachTextTertiary)
                }
                .padding(AmachSpacing.md)
            }
            .amachCard()
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(AmachType.tiny)
            .foregroundStyle(Color.amachTextSecondary)
            .padding(.horizontal, AmachSpacing.xs)
    }

    private func settingsRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(label)
                .font(AmachType.body)
                .foregroundStyle(Color.amachTextPrimary)
            Spacer()
            content()
        }
        .padding(AmachSpacing.md)
    }

    private func createIssueReport() {
        do {
            let url = try IssueReportService().createReport(
                settings: settingsService.settings,
                sessions: sessionService.sessions,
                sessionService: sessionService,
                subscriptionService: subscriptionService,
                watchService: watchConnectivity
            )
            issueReportURL = url
            showIssueReportSheet = true
        } catch {
            issueReportError = error.localizedDescription
        }
    }
}

private extension AppSettings.PacerStyle {
    var displayName: String {
        switch self {
        case .ring:    return "Expanding Ring"
        case .text:    return "Text Cue"
        case .minimal: return "Minimal"
        }
    }
    var description: String {
        switch self {
        case .ring:    return "Animated ring grows with each breath"
        case .text:    return "In / Out text prompts"
        case .minimal: return "Countdown timer only"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettingsService())
        .environmentObject(SubscriptionService())
        .environmentObject(SessionService())
        .environmentObject(WatchConnectivityService())
}
