import SwiftUI

struct CleanupView: View {
    @EnvironmentObject var viewModel: ContactViewModel
    @State private var selectedContacts = Set<UUID>()
    @State private var showDeleteConfirmation = false
    @State private var showDeleteAllConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView(viewModel.loadingMessage)
                } else if viewModel.incompleteContacts.isEmpty {
                    ContentUnavailableView(
                        "No Incomplete Contacts",
                        systemImage: "checkmark.circle.fill",
                        description: Text("All your contacts have proper contact information.")
                    )
                } else {
                    List(selection: $selectedContacts) {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Incomplete Contacts")
                                        .font(.headline)
                                }
                                Text("These contacts have names but no email addresses or phone numbers. " +
                                     "They may be outdated or incomplete entries.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        }

                        Section {
                            ForEach(viewModel.incompleteContacts) { contact in
                                IncompleteContactRow(
                                    contact: contact,
                                    isSelected: selectedContacts.contains(contact.id)
                                )
                                    .tag(contact.id)
                            }
                        } header: {
                            HStack {
                                Text("\(viewModel.incompleteContacts.count) contacts")
                                Spacer()
                                let allSelected = selectedContacts.count == viewModel.incompleteContacts.count
                                Button(allSelected ? "Deselect All" : "Select All") {
                                    if selectedContacts.count == viewModel.incompleteContacts.count {
                                        selectedContacts.removeAll()
                                    } else {
                                        selectedContacts = Set(viewModel.incompleteContacts.map { $0.id })
                                    }
                                }
                                .font(.caption)
                            }
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                }
            }
            .navigationTitle("Cleanup")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Selected (\(selectedContacts.count))", systemImage: "trash")
                        }
                        .disabled(selectedContacts.isEmpty)

                        Button(role: .destructive) {
                            showDeleteAllConfirmation = true
                        } label: {
                            Label("Delete All Incomplete", systemImage: "trash.fill")
                        }
                        .disabled(viewModel.incompleteContacts.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                ToolbarItem(placement: .bottomBar) {
                    if !selectedContacts.isEmpty {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete \(selectedContacts.count) Selected", systemImage: "trash")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            }
            .alert("Delete Selected Contacts?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete \(selectedContacts.count)", role: .destructive) {
                    Task {
                        let contactsToDelete = viewModel.incompleteContacts.filter { selectedContacts.contains($0.id) }
                        await viewModel.deleteIncompleteContacts(contactsToDelete)
                        selectedContacts.removeAll()
                    }
                }
            } message: {
                Text("This will permanently delete \(selectedContacts.count) contacts " +
                     "from your Apple Contacts. This cannot be undone.")
            }
            .alert("Delete All Incomplete Contacts?", isPresented: $showDeleteAllConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All (\(viewModel.incompleteContacts.count))", role: .destructive) {
                    Task {
                        await viewModel.deleteAllIncompleteContacts()
                        selectedContacts.removeAll()
                    }
                }
            } message: {
                Text("This will permanently delete all \(viewModel.incompleteContacts.count) " +
                     "incomplete contacts from your Apple Contacts. This cannot be undone.")
            }
            .alert("Success", isPresented: .constant(viewModel.successMessage != nil && !viewModel.isLoading)) {
                Button("OK") { viewModel.clearMessages() }
            } message: {
                Text(viewModel.successMessage ?? "")
            }
        }
    }
}

struct IncompleteContactRow: View {
    let contact: ContactData
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatarView(contact: contact, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.displayName)
                    .font(.headline)

                if !contact.company.isEmpty {
                    Text(contact.company)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption2)
                    Text("No email or phone")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    CleanupView()
        .environmentObject(ContactViewModel())
}
