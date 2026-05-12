import SwiftUI
import AmachBreatheShared

/// Two-step email OTP sheet for connecting a Privy embedded wallet.
/// Mirrors AmachHealth-iOS ConnectWalletSheet. Auto-dismisses on successful connect.
struct ConnectWalletSheet: View {

    @EnvironmentObject private var wallet: WalletService
    @Environment(\.dismiss) private var dismiss

    private enum Step { case email, code }

    @State private var step: Step = .email
    @State private var emailInput = ""
    @State private var codeInput = ""
    @FocusState private var emailFocused: Bool
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.amachSurface.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    inputs
                        .padding(.horizontal, AmachSpacing.lg)
                    Spacer()
                    footer
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.amachTextSecondary)
                }
            }
        }
        .onChange(of: wallet.isConnected) { _, connected in
            if connected { dismiss() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: AmachSpacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.amachPrimary.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: AmachType.iconSm))
                    .foregroundStyle(Color.amachPrimary)
            }
            .padding(.top, AmachSpacing.xl)
            Text(step == .email ? "Connect Your Wallet" : "Check Your Email")
                .font(AmachType.h2)
                .foregroundStyle(Color.amachTextPrimary)
            Text(step == .email
                 ? "Enter the email you use on amachhealth.com"
                 : "Enter the 6-digit code sent to\n\(emailInput)")
                .font(AmachType.caption)
                .foregroundStyle(Color.amachTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AmachSpacing.xl)
        }
        .padding(.bottom, AmachSpacing.xl)
    }

    // MARK: - Inputs

    @ViewBuilder
    private var inputs: some View {
        VStack(spacing: AmachSpacing.md) {
            if step == .email {
                emailStep
            } else {
                codeStep
            }
            if let err = wallet.error {
                Text(err)
                    .font(AmachType.tiny)
                    .foregroundStyle(Color.amachDestructive)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var emailStep: some View {
        VStack(spacing: AmachSpacing.sm) {
            TextField("you@example.com", text: $emailInput)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($emailFocused)
                .textFieldStyle(AmachTextFieldStyle())
                .onAppear { emailFocused = true }
            connectButton(
                title: "Send Code",
                isEnabled: isValidEmail(emailInput)
            ) {
                Task {
                    do {
                        try await wallet.sendEmailCode(
                            to: emailInput.trimmingCharacters(in: .whitespaces))
                        withAnimation { step = .code }
                    } catch {
                        // WalletService publishes the message shown below the form.
                    }
                }
            }
        }
    }

    private var codeStep: some View {
        VStack(spacing: AmachSpacing.sm) {
            TextField("123456", text: $codeInput)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .focused($codeFocused)
                .textFieldStyle(AmachTextFieldStyle())
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .onChange(of: codeInput) { _, v in
                    if v.count > 6 { codeInput = String(v.prefix(6)) }
                }
                .onAppear { codeFocused = true }
            connectButton(title: "Verify Code", isEnabled: codeInput.count == 6) {
                Task {
                    do {
                        try await wallet.loginWithEmailCode(codeInput)
                    } catch {
                        // WalletService publishes the message shown below the form.
                    }
                }
            }
            Button {
                withAnimation {
                    codeInput = ""
                    wallet.error = nil
                    step = .email
                }
            } label: {
                Label("Use a different email", systemImage: "chevron.left")
                    .font(AmachType.caption)
                    .foregroundStyle(Color.amachTextSecondary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Text("Your data stays private. We never store passwords.")
            .font(AmachType.tiny)
            .foregroundStyle(Color.amachTextSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AmachSpacing.xl)
            .padding(.bottom, AmachSpacing.lg)
    }

    // MARK: - Button

    private func connectButton(
        title: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                if wallet.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                        .font(AmachType.body.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(isEnabled ? Color.amachPrimary : Color.amachPrimary.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
        }
        .disabled(!isEnabled || wallet.isLoading)
    }

    private func isValidEmail(_ email: String) -> Bool {
        let s = email.trimmingCharacters(in: .whitespaces)
        return s.contains("@") && s.contains(".") && s.count > 4
    }
}

// MARK: - AmachTextFieldStyle

private struct AmachTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .padding(.horizontal, AmachSpacing.md)
            .padding(.vertical, 14)
            .background(Color.amachElevated)
            .clipShape(RoundedRectangle(cornerRadius: AmachRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: AmachRadius.md)
                    .strokeBorder(Color.amachPrimary.opacity(0.18), lineWidth: 1)
            )
            .font(AmachType.body)
            .foregroundStyle(Color.amachTextPrimary)
    }
}

#Preview {
    ConnectWalletSheet()
        .environmentObject(WalletService.shared)
}
