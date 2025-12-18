import SwiftUI
import Contacts

struct SettingsView: View {
    @EnvironmentObject var viewModel: ContactViewModel
    @AppStorage("similarityThreshold") private var threshold: Double = 0.90
    @AppStorage("autoMergeHighConfidence") private var autoMergeHighConfidence = false
    @State private var contactsPermissionStatus: CNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            List {
                // Duplicate Detection Settings
                Section("Duplicate Detection") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Similarity Threshold")
                            Spacer()
                            Text("\(Int(threshold * 100))%")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $threshold, in: 0.5...0.95, step: 0.05)
                            .onChange(of: threshold) { _, newValue in
                                viewModel.similarityThreshold = newValue
                            }
                    }

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Lower threshold")
                                .font(.caption)
                            Text("More matches, less accurate")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Higher threshold")
                                .font(.caption)
                            Text("Fewer matches, more accurate")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Permissions Section
                Section("Permissions") {
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .foregroundColor(.accentColor)
                        Text("Contacts Access")
                        Spacer()
                        Text(permissionStatusText)
                            .foregroundColor(permissionStatusColor)
                    }

                    if contactsPermissionStatus == .denied || contactsPermissionStatus == .restricted {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Open Settings", systemImage: "gear")
                        }
                    }
                }

                // Statistics
                Section("Current Session") {
                    StatisticRow(label: "Contacts Loaded", value: "\(viewModel.contacts.count)")
                    StatisticRow(label: "Duplicate Groups", value: "\(viewModel.duplicateGroups.count)")
                    StatisticRow(label: "Incomplete Contacts", value: "\(viewModel.incompleteContacts.count)")
                }

                // Data Section
                Section {
                    Button {
                        viewModel.clearDismissedDuplicates()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset Dismissed Duplicates")
                        }
                    }

                    Button {
                        viewModel.loadContacts()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Reload Contacts")
                        }
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Reset dismissed duplicates will show duplicate suggestions " +
                         "you previously marked as 'Not a Duplicate'.")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                contactsPermissionStatus = CNContactStore.authorizationStatus(for: .contacts)
            }
        }
    }

    var permissionStatusText: String {
        switch contactsPermissionStatus {
        case .authorized, .limited: return "Granted"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Asked"
        @unknown default: return "Unknown"
        }
    }

    var permissionStatusColor: Color {
        switch contactsPermissionStatus {
        case .authorized, .limited: return .green
        case .denied, .restricted: return .red
        case .notDetermined: return .secondary
        @unknown default: return .secondary
        }
    }
}

struct StatisticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(ContactViewModel())
}
