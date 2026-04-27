import SwiftUI
import AmachBreatheShared

struct SettingsView: View {

    @EnvironmentObject private var settingsService: AppSettingsService

    var body: some View {
        NavigationStack {
            ZStack {
                Color.amachBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: AmachSpacing.sectionSpacing) {
                        breathingSection
                        audioSection
                        pacerSection
                    }
                    .padding(AmachSpacing.screenEdge)
                    .padding(.bottom, AmachSpacing.xxl)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Sections

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
            }
            .background(Color.amachSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .background(Color.amachSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .background(Color.amachSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
}
