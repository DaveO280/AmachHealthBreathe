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
        .onAppear {
            restorePendingCodeState()
        }
        .onChange(of: wallet.pendingEmail) { _, pending in
            if let pending {
                emailInput = pending
                codeInput = ""
                withAnimation { step = .code }
            } else if step == .code && !wallet.isConnected {
                codeInput = ""
                withAnimation { step = .email }
            }
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
                 ? "Use your Amach Health email. We'll send a one-time code."
                 : "Enter the 6-digit code sent to\n\(displayEmail)")
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
                isEnabled: true
            ) {
                Task {
                    do {
                        try await wallet.sendEmailCode(
                            to: emailInput.trimmingCharacters(in: .whitespaces))
                        withAnimation { step = .code }
                    } catch {
                        showFallbackError(error)
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
            Text("Code pending for \(displayEmail). You can close this sheet and continue here while the code is pending.")
                .font(AmachType.tiny)
                .foregroundStyle(Color.amachTextSecondary)
                .multilineTextAlignment(.center)
            connectButton(title: "Verify Code", isEnabled: codeInput.count == 6) {
                Task {
                    do {
                        try await wallet.loginWithEmailCode(codeInput)
                    } catch {
                        showFallbackError(error)
                    }
                }
            }
            Button {
                Task {
                    do {
                        codeInput = ""
                        try await wallet.sendEmailCode(to: displayEmail)
                    } catch {
                        showFallbackError(error)
                    }
                }
            } label: {
                Text("Resend code")
                    .font(AmachType.caption.weight(.semibold))
                    .foregroundStyle(Color.amachPrimary)
            }
            .disabled(wallet.isLoading)
            Button {
                withAnimation {
                    resetPendingCode()
                }
            } label: {
                Label("Change or cancel email", systemImage: "chevron.left")
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

    private var displayEmail: String {
        wallet.pendingEmail ?? emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func restorePendingCodeState() {
        guard let pending = wallet.pendingEmail else { return }
        emailInput = pending
        step = .code
    }

    private func resetPendingCode() {
        codeInput = ""
        wallet.clearPendingEmailCode()
        step = .email
        emailFocused = true
    }

    private func showFallbackError(_ error: Error) {
        if wallet.error == nil {
            wallet.error = error.localizedDescription
        }
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
