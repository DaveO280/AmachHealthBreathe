import SwiftUI
import AmachBreatheShared

public struct QuickStartView: View {

    @EnvironmentObject private var runner: WatchSessionRunner

    @State private var selectedBPM: Double = 5.5
    @State private var selectedDuration: Int = 300
    @State private var isStarting: Bool = false

    private let bpmOptions: [Double] = [4.5, 5.0, 5.5, 6.0, 6.5, 7.0]
    private let durationOptions: [(label: String, seconds: Int)] = [
        ("5 min", 300), ("10 min", 600), ("15 min", 900)
    ]

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Breathe")
                        .font(.headline)
                        .foregroundStyle(Color.amachTextPrimary)

                    bpmPicker
                    durationPicker
                    startButton
                }
                .padding(.horizontal, 8)
            }
        }
        .task { try? await runner.requestHealthKitAuthorization() }
    }

    private var bpmPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Rate")
                .font(.caption2)
                .foregroundStyle(Color.amachTextSecondary)
            Picker("BPM", selection: $selectedBPM) {
                ForEach(bpmOptions, id: \.self) { bpm in
                    Text("\(bpm, specifier: "%.1f") BPM").tag(bpm)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 64)
        }
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Duration")
                .font(.caption2)
                .foregroundStyle(Color.amachTextSecondary)
            HStack(spacing: 6) {
                ForEach(durationOptions, id: \.seconds) { opt in
                    Button(opt.label) {
                        selectedDuration = opt.seconds
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedDuration == opt.seconds
                                  ? Color.amachPrimary
                                  : Color.amachSurface)
                    )
                    .foregroundStyle(Color.amachTextPrimary)
                }
            }
        }
    }

    private var startButton: some View {
        Button {
            startSession()
        } label: {
            if isStarting {
                ProgressView().tint(Color.amachTextPrimary)
            } else {
                Text("Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 10)
        .background(Color.amachPrimary)
        .foregroundStyle(Color.amachTextPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .disabled(isStarting)
    }

    private func startSession() {
        isStarting = true
        Task {
            try? await runner.startSession(bpm: selectedBPM, durationSeconds: selectedDuration)
            await MainActor.run { isStarting = false }
        }
    }
}
