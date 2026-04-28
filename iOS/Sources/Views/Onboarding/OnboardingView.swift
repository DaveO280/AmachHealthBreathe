import SwiftUI
import AmachBreatheShared

/// Five-page first-launch onboarding shown as a fullScreenCover.
/// On completion: writes default ratio, reminder times, and schedules notifications.
struct OnboardingView: View {

    @EnvironmentObject private var settingsService: AppSettingsService
    @EnvironmentObject private var calibrationStore: CalibrationStore
    @EnvironmentObject private var onboardingService: OnboardingService

    @State private var currentPage = 0
    @State private var selectedRatio: BreathRatio = .fourToSix
    @State private var selectedDuration = 300        // seconds
    @State private var reminderTimes: [Int] = []
    @State private var notificationGranted = false

    private let totalPages = 5

    var body: some View {
        ZStack {
            Color.amachBg.ignoresSafeArea()
            VStack(spacing: 0) {
                progressDots
                    .padding(.top, AmachSpacing.lg)

                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    permissionsPage.tag(1)
                    calibrationPage.tag(2)
                    sessionLengthPage.tag(3)
                    reminderPage.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)
            }
        }
    }

    // MARK: - Progress dots

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalPages, id: \.self) { i in
                Circle()
                    .fill(i == currentPage ? Color.amachPrimary : Color.amachSurface)
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut, value: currentPage)
            }
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: AmachSpacing.lg) {
            Spacer()

            AmachBrandMark(layout: .stacked)

            Spacer()

            VStack(spacing: AmachSpacing.sm) {
                Text("Resonant breathing, effortlessly calibrated.")
                    .font(AmachType.body)
                    .foregroundStyle(Color.amachPrimary)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                Text("Synchronise your breath with your heart rate variability. Your Apple Watch finds your perfect frequency.")
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AmachSpacing.lg)
            }

            Spacer()

            Button { advance() } label: {
                Text("Get Started")
                    .font(AmachType.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.amachPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
            }
            .padding(.horizontal, AmachSpacing.screenEdge)
            .padding(.bottom, AmachSpacing.xl)
        }
    }

    // MARK: - Page 2: Permissions

    private var permissionsPage: some View {
        ScrollView {
            VStack(spacing: AmachSpacing.lg) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: AmachType.iconHero))
                    .foregroundStyle(Color.amachPrimary)
                    .padding(.top, AmachSpacing.xl)

                VStack(spacing: AmachSpacing.xs) {
                    Text("Permissions")
                        .font(AmachType.h1)
                        .foregroundStyle(Color.amachTextPrimary)
                    Text("Amach Breathe needs access to HealthKit for heart rate data and notifications for daily reminders.")
                        .font(AmachType.caption)
                        .foregroundStyle(Color.amachTextSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: AmachSpacing.sm) {
                    permissionRow(
                        icon: "heart.fill", iconColor: Color.amachDestructive,
                        title: "Health",
                        detail: "Heart rate during breathing sessions"
                    )
                    permissionRow(
                        icon: "bell.fill", iconColor: Color.amachWarning,
                        title: "Notifications",
                        detail: "Optional daily breathing reminders"
                    )
                }
                .padding(.horizontal, AmachSpacing.screenEdge)

                Button {
                    Task {
                        notificationGranted = await NotificationService.shared.requestAuthorization()
                        advance()
                    }
                } label: {
                    Text("Allow & Continue")
                        .font(AmachType.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.amachPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
                }
                .padding(.horizontal, AmachSpacing.screenEdge)

                Button("Skip") { advance() }
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
                    .padding(.bottom, AmachSpacing.xl)
            }
        }
    }

    private func permissionRow(icon: String, iconColor: Color, title: String, detail: String) -> some View {
        HStack(spacing: AmachSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AmachType.body)
                    .foregroundStyle(Color.amachTextPrimary)
                Text(detail)
                    .font(AmachType.tiny)
                    .foregroundStyle(Color.amachTextSecondary)
            }
            Spacer()
        }
        .padding(AmachSpacing.md)
        .background(Color.amachSurface)
        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.sm))
    }

    // MARK: - Page 3: Calibration

    private var calibrationPage: some View {
        let hasCalibration = calibrationStore.record != nil
        return onboardingPage(
            icon: hasCalibration ? "checkmark.circle.fill" : "waveform.path.ecg",
            title: hasCalibration ? "Rate Found" : "Find Your Rate",
            subtitle: hasCalibration
                ? "Resonance at \(String(format: "%.1f", calibrationStore.resonanceBPM)) BPM"
                : "Your Apple Watch will measure your resonance frequency.",
            body: hasCalibration
                ? "Your resonance BPM is saved. You're ready to breathe."
                : "Run a short calibration on your Watch to personalise sessions. You can skip this and do it later.",
            cta: "Continue"
        ) { advance() }
    }

    // MARK: - Page 4: Session Length

    private var sessionLengthPage: some View {
        VStack(spacing: AmachSpacing.lg) {
            Image(systemName: "clock.fill")
                .font(.system(size: AmachType.iconHero))
                .foregroundStyle(Color.amachPrimary)
                .padding(.top, AmachSpacing.xl)

            VStack(spacing: AmachSpacing.xs) {
                Text("Default Session")
                    .font(AmachType.h1)
                    .foregroundStyle(Color.amachTextPrimary)
                Text("How long is your typical breathing session?")
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: AmachSpacing.sm) {
                ForEach([(5, 300), (10, 600), (15, 900)], id: \.1) { label, seconds in
                    Button {
                        selectedDuration = seconds
                    } label: {
                        HStack {
                            Text("\(label) minutes")
                                .font(AmachType.body)
                                .foregroundStyle(Color.amachTextPrimary)
                            Spacer()
                            if selectedDuration == seconds {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.amachPrimary)
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding(AmachSpacing.md)
                        .background(Color.amachSurface)
                        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.sm))
                    }
                }
            }
            .padding(.horizontal, AmachSpacing.screenEdge)

            Spacer()

            Button {
                advance()
            } label: {
                Text("Continue")
                    .font(AmachType.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.amachPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
            }
            .padding(.horizontal, AmachSpacing.screenEdge)
            .padding(.bottom, AmachSpacing.xl)
        }
    }

    // MARK: - Page 5: Reminders

    private var reminderPage: some View {
        VStack(spacing: AmachSpacing.lg) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: AmachType.iconHero))
                .foregroundStyle(Color.amachWarning)
                .padding(.top, AmachSpacing.xl)

            VStack(spacing: AmachSpacing.xs) {
                Text("Daily Reminder")
                    .font(AmachType.h1)
                    .foregroundStyle(Color.amachTextPrimary)
                Text("Set a daily time to breathe. You can add up to 2 reminders in Settings.")
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
                    .multilineTextAlignment(.center)
            }

            ReminderTimePicker(selectedTimes: $reminderTimes)
                .padding(.horizontal, AmachSpacing.screenEdge)

            Spacer()

            VStack(spacing: AmachSpacing.sm) {
                Button {
                    completeOnboarding()
                } label: {
                    Text("Done")
                        .font(AmachType.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.amachPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
                }
                Button("Skip Reminders") { completeOnboarding() }
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
            }
            .padding(.horizontal, AmachSpacing.screenEdge)
            .padding(.bottom, AmachSpacing.xl)
        }
    }

    // MARK: - Page builder

    private func onboardingPage(
        icon: String,
        title: String,
        subtitle: String,
        body: String,
        cta: String,
        shimmerTitle: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: AmachSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: AmachType.iconLg))
                .foregroundStyle(Color.amachPrimary)
                .padding(.top, AmachSpacing.xl)

            VStack(spacing: AmachSpacing.sm) {
                Group {
                    if shimmerTitle {
                        Text(title)
                            .foregroundStyle(Color.amachPrimaryWordmark)
                            .amachShimmer(delay: 0.8)
                    } else {
                        Text(title)
                            .foregroundStyle(Color.amachTextPrimary)
                    }
                }
                .font(AmachType.h1)
                Text(subtitle)
                    .font(AmachType.body)
                    .foregroundStyle(Color.amachPrimary)
                    .fontWeight(.medium)
                Text(body)
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AmachSpacing.lg)
            }

            Spacer()

            Button(action: action) {
                Text(cta)
                    .font(AmachType.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.amachPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
            }
            .padding(.horizontal, AmachSpacing.screenEdge)
            .padding(.bottom, AmachSpacing.xl)
        }
    }

    // MARK: - Actions

    private func advance() {
        withAnimation { currentPage = min(currentPage + 1, totalPages - 1) }
    }

    private func completeOnboarding() {
        // Write selected settings
        settingsService.updateRatio(selectedRatio)
        settingsService.updateReminders(reminderTimes)

        // Schedule notifications
        if !reminderTimes.isEmpty {
            Task { await NotificationService.shared.scheduleReminders(reminderTimes) }
        }

        // Mark complete
        onboardingService.markComplete()
    }
}

// MARK: - Reminder time picker (inline)

private struct ReminderTimePicker: View {

    @Binding var selectedTimes: [Int]
    @State private var pickerDate = Date()
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: AmachSpacing.sm) {
            if selectedTimes.isEmpty {
                Button {
                    showPicker = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.amachPrimary)
                        Text("Set a reminder time")
                            .font(AmachType.body)
                            .foregroundStyle(Color.amachPrimary)
                    }
                    .padding(AmachSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.amachSurface)
                    .clipShape(RoundedRectangle(cornerRadius: AmachRadius.sm))
                }
            } else {
                ForEach(Array(selectedTimes.enumerated()), id: \.offset) { _, seconds in
                    HStack {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(Color.amachWarning)
                        Text(NotificationScheduler.displayTime(secondsFromMidnight: seconds))
                            .font(AmachType.body)
                            .foregroundStyle(Color.amachTextPrimary)
                        Spacer()
                        Button {
                            selectedTimes.removeAll { $0 == seconds }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(Color.amachDestructive)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(AmachSpacing.md)
                    .background(Color.amachSurface)
                    .clipShape(RoundedRectangle(cornerRadius: AmachRadius.sm))
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                ZStack {
                    Color.amachBg.ignoresSafeArea()
                    DatePicker("", selection: $pickerDate, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
                .navigationTitle("Reminder Time")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add") {
                            let cal = Calendar.current
                            let comps = cal.dateComponents([.hour, .minute], from: pickerDate)
                            let seconds = (comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60
                            if !selectedTimes.contains(seconds) {
                                selectedTimes.append(seconds)
                            }
                            showPicker = false
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.amachPrimary)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showPicker = false }
                            .foregroundStyle(Color.amachTextSecondary)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}
