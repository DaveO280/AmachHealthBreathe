import SwiftUI
import AmachBreatheShared

/// Shows a compact wallet status strip at the top of a view.
/// Disconnected: shows "Connect" button that presents ConnectWalletSheet.
/// Connected: shows abbreviated address + sync indicator.
struct WalletStatusBanner: View {

    @EnvironmentObject private var wallet: WalletService
    @EnvironmentObject private var sessionService: SessionService
    @State private var showConnect = false

    var body: some View {
        if wallet.isConnected {
            connectedBanner
        } else {
            disconnectedBanner
        }
    }

    // MARK: - Connected

    private var connectedBanner: some View {
        HStack(spacing: AmachSpacing.sm) {
            Circle()
                .fill(Color.amachPrimary)
                .frame(width: 8, height: 8)
            Text(abbreviatedAddress)
                .font(AmachType.tiny)
                .foregroundStyle(Color.amachTextSecondary)
            Spacer()
            if sessionService.isSyncing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Syncing…")
                        .font(AmachType.tiny)
                        .foregroundStyle(Color.amachTextTertiary)
                }
            } else {
                let pending = sessionService.sessions.filter { $0.uploadStatus == .pending }.count
                if pending > 0 {
                    Text("\(pending) pending")
                        .font(AmachType.tiny)
                        .foregroundStyle(Color(hex: "F59E0B"))
                }
            }
        }
        .padding(.horizontal, AmachSpacing.md)
        .padding(.vertical, AmachSpacing.xs)
        .background(Color.amachSurface)
    }

    // MARK: - Disconnected

    private var disconnectedBanner: some View {
        HStack(spacing: AmachSpacing.sm) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 12))
                .foregroundStyle(Color.amachTextTertiary)
            Text("Not connected — sessions saved locally")
                .font(AmachType.tiny)
                .foregroundStyle(Color.amachTextSecondary)
            Spacer()
            Button("Connect") { showConnect = true }
                .font(AmachType.tiny.weight(.semibold))
                .foregroundStyle(Color.amachPrimary)
        }
        .padding(.horizontal, AmachSpacing.md)
        .padding(.vertical, AmachSpacing.xs)
        .background(Color.amachSurface)
        .sheet(isPresented: $showConnect) {
            ConnectWalletSheet()
        }
    }

    // MARK: - Helpers

    private var abbreviatedAddress: String {
        guard let addr = wallet.address, addr.count > 10 else {
            return wallet.address ?? ""
        }
        let prefix = addr.prefix(6)
        let suffix = addr.suffix(4)
        return "\(prefix)…\(suffix)"
    }
}

#Preview {
    VStack(spacing: 0) {
        WalletStatusBanner()
        Spacer()
    }
    .environmentObject(WalletService.shared)
    .environmentObject(SessionService())
}
