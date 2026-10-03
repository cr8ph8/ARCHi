import SwiftUI

@MainActor
struct MarketplaceConnectionBar: View {
    @ObservedObject var catalog: MarketplaceCatalogStore
    @State private var showsAccount = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: catalog.connected ? "network" : "network.slash")
                    .foregroundStyle(WorkspaceTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(catalog.account.map { "@\($0.handle)" } ?? "Design catalog")
                        .font(.system(size: 12, weight: .medium))
                    Text(catalog.connected ? "Local catalog · designs shared on this Mac" : "Included designs are ready. Connect for shared designs.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if catalog.isBusy { ProgressView().controlSize(.small).accessibilityLabel("Catalog request in progress") }
                Button(catalog.account != nil ? "Account" : catalog.connected ? "Sign in" : "Connect catalog") { showsAccount = true }
                    .buttonStyle(WorkspaceActionStyle())
                    .accessibilityIdentifier("marketplace.account")
            }
            if let error = catalog.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("marketplace.catalog.error")
            }
            if catalog.hasPendingMutation {
                Button("Try again", systemImage: "arrow.clockwise") { Task { await catalog.retryPending() } }
                    .disabled(catalog.isBusy)
                    .help("Retries the pending action without submitting it twice.")
                    .accessibilityIdentifier("marketplace.catalog.retry")
            }
        }
        .padding(.vertical, 5)
        .sheet(isPresented: $showsAccount) { MarketplaceAccountView(catalog: catalog) }
    }
}

@MainActor
struct MarketplaceAccountView: View {
    @ObservedObject var catalog: MarketplaceCatalogStore
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var handle = ""
    @State private var displayName = ""
    @State private var password = ""

    private var validCredentials: Bool {
        handle.range(of: "\\A[a-z][a-z0-9_]{2,31}\\z", options: .regularExpression) != nil
            && (12...128).contains(password.unicodeScalars.count) && password.utf8.count <= 512
            && MarketplaceProvenance.validText(password, maximum: 512, required: true)
            && (!creating || MarketplaceProvenance.validText(displayName, maximum: 48, required: true))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("Marketplace account").font(.title2)
                Spacer()
                Button("Done") { password = ""; dismiss() }.keyboardShortcut(.cancelAction)
                    .buttonStyle(WorkspaceActionStyle())
                    .accessibilityIdentifier("marketplace.account.done")
            }
            if !catalog.connected {
                Text("Connect to the catalog running on this Mac to browse shared designs and save them to an account.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Local catalog address").font(.caption)
                TextField("Service address", text: $catalog.endpointText)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("marketplace.account.endpoint")
                Button("Connect catalog") { Task { await catalog.connect() } }
                    .buttonStyle(WorkspaceActionStyle(prominent: true)).disabled(catalog.isBusy)
                    .accessibilityIdentifier("marketplace.account.connect")
                Text("The catalog must be running first. The usual address is http://127.0.0.1:47831.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let account = catalog.account {
                Label(account.displayName, systemImage: "person.crop.circle").font(.title3)
                Text("@\(account.handle)").foregroundStyle(.secondary)
                Text("Your library and published designs stay in this Mac’s catalog. Download a design to add it to your companion’s collection.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Sign out") { Task { await catalog.signOut() } }
                    .disabled(catalog.isBusy || catalog.hasPendingMutation)
                    .accessibilityIdentifier("marketplace.account.signout")
            } else {
                Picker("Account action", selection: $creating) {
                    Text("Sign in").tag(false)
                    Text("Create account").tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("marketplace.account.mode")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Username").font(.caption)
                    TextField("creator_name", text: $handle).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("marketplace.account.handle")
                    Text("3–32 lowercase letters, numbers or underscores; start with a letter.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if creating {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Display name").font(.caption)
                        TextField("Your creator name", text: $displayName).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("marketplace.account.display-name")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Password").font(.caption)
                    SecureField("12–128 characters", text: $password).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("marketplace.account.password")
                }
                Button(creating ? "Create account" : "Sign in") {
                    let submittedPassword = password
                    Task {
                        if creating {
                            if await catalog.createAccount(handle: handle, displayName: displayName, password: submittedPassword) {
                                creating = false; password = ""
                            }
                        } else {
                            await catalog.signIn(handle: handle, password: submittedPassword)
                            if catalog.account != nil { password = ""; dismiss() }
                        }
                    }
                }
                .buttonStyle(WorkspaceActionStyle(prominent: true))
                .disabled(!validCredentials || catalog.isBusy)
                .accessibilityIdentifier("marketplace.account.submit")
                Text("This account is for the catalog on this Mac. You’ll need to sign in again after closing ARCHi.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if catalog.isBusy { ProgressView().controlSize(.small) }
            Text(catalog.errorMessage ?? catalog.message).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("marketplace.account.status")
        }
        .padding(24).frame(width: 470).background(WorkspaceTheme.background)
    }
}
