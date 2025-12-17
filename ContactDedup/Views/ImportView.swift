import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var viewModel: ContactViewModel
    @ObservedObject private var authManager = GoogleAuthManager.shared
    @State private var showingApplePermissionAlert = false
    @State private var showingLinkedInFilePicker = false

    private var linkedInLastImportText: String {
        guard let date = viewModel.lastLinkedInImportDate else {
            return "Never imported"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Last: \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    var body: some View {
        NavigationStack {
            List {
                // Apple Contacts Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "apple.logo")
                                .font(.title2)
                                .foregroundColor(.primary)
                            VStack(alignment: .leading) {
                                Text("Apple Contacts")
                                    .font(.headline)
                                Text("Sync with your device contacts")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button {
                            viewModel.loadContacts()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Sync Apple Contacts")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isLoading)
                    }
                    .padding(.vertical, 8)
                } footer: {
                    Text("Loads contacts from your Apple Contacts app. Changes you make (merges, deletions) will sync back to Apple Contacts.")
                }

                // Google Accounts Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "g.circle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                            VStack(alignment: .leading) {
                                Text("Google Contacts")
                                    .font(.headline)
                                Text("\(authManager.accounts.count) account\(authManager.accounts.count == 1 ? "" : "s") connected")
                                    .font(.caption)
                                    .foregroundColor(authManager.accounts.isEmpty ? .secondary : .green)
                            }
                            Spacer()
                            Button {
                                Task {
                                    do {
                                        try await authManager.addAccount()
                                    } catch {
                                        viewModel.errorMessage = error.localizedDescription
                                    }
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                            }
                        }

                        // List connected accounts
                        ForEach(authManager.accounts) { account in
                            GoogleAccountRow(
                                account: account,
                                lastImportDate: viewModel.lastImportDate(for: account.email),
                                onImport: {
                                    Task {
                                        await viewModel.importFromGoogle(account: account)
                                    }
                                },
                                onRemove: {
                                    authManager.removeAccount(account.email)
                                },
                                isImporting: viewModel.isImporting
                            )
                        }

                        // Import from all accounts
                        if authManager.accounts.count > 1 {
                            Button {
                                Task {
                                    await viewModel.importFromAllGoogleAccounts()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.arrow.down.on.square")
                                    Text("Import from All Accounts")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(viewModel.isImporting)
                        }

                        // Sign in button when no accounts
                        if authManager.accounts.isEmpty {
                            Button {
                                Task {
                                    do {
                                        try await authManager.signIn()
                                    } catch {
                                        viewModel.errorMessage = error.localizedDescription
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "person.badge.key")
                                    Text("Sign in with Google")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }
                    .padding(.vertical, 8)
                } footer: {
                    Text("Import contacts from your Google accounts. Duplicates will be detected after import. Tap + to add another account.")
                }

                // LinkedIn Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "link.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("LinkedIn Connections")
                                    .font(.headline)
                                Text(linkedInLastImportText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button {
                            showingLinkedInFilePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                Text("Select LinkedIn CSV")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(viewModel.isImporting)
                    }
                    .padding(.vertical, 8)
                } footer: {
                    Text("Export your connections from LinkedIn Settings > Data Privacy > Get a copy of your data > Connections. Only contacts with email addresses will be imported.")
                }

                // Import Progress
                if viewModel.isImporting {
                    Section {
                        VStack(spacing: 12) {
                            ProgressView(value: viewModel.importProgress)
                            Text(viewModel.loadingMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Statistics
                Section("Statistics") {
                    StatRow(
                        title: "Total Contacts",
                        value: "\(viewModel.contacts.count)",
                        icon: "person.crop.circle"
                    )
                    StatRow(
                        title: "Duplicate Groups",
                        value: "\(viewModel.duplicateGroups.count)",
                        icon: "person.2.fill",
                        color: viewModel.duplicateGroups.isEmpty ? .green : .orange
                    )
                    StatRow(
                        title: "Incomplete Contacts",
                        value: "\(viewModel.incompleteContacts.count)",
                        icon: "exclamationmark.triangle.fill",
                        color: viewModel.incompleteContacts.isEmpty ? .green : .orange
                    )
                }
            }
            .navigationTitle("Import")
            .fileImporter(
                isPresented: $showingLinkedInFilePicker,
                allowedContentTypes: [UTType.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        Task {
                            await viewModel.importFromLinkedIn(url: url)
                        }
                    }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.clearMessages() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("Success", isPresented: .constant(viewModel.successMessage != nil && !viewModel.isLoading && !viewModel.isImporting)) {
                Button("OK") { viewModel.clearMessages() }
            } message: {
                Text(viewModel.successMessage ?? "")
            }
        }
    }
}

struct GoogleAccountRow: View {
    let account: GoogleAccount
    let lastImportDate: Date?
    let onImport: () -> Void
    let onRemove: () -> Void
    let isImporting: Bool

    private var lastImportText: String {
        guard let date = lastImportDate else { return "Never imported" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Last: \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(account.isActive ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.email)
                    .font(.subheadline)
                Text(lastImportText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if !account.isActive {
                    Text("Tap Import to reconnect")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            Spacer()
            Button("Import") {
                onImport()
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(isImporting)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

struct StatRow: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .accentColor

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}

struct BulletPoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
}

#Preview {
    ImportView()
        .environmentObject(ContactViewModel())
}
