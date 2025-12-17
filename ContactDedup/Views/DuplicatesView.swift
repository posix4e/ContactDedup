import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject var viewModel: ContactViewModel
    @State private var selectedGroup: DuplicateGroup?
    @State private var showMergeConfirmation = false
    @State private var mergeType: DuplicateMatchType?

    var phoneGroups: [DuplicateGroup] {
        viewModel.duplicateGroups.filter { $0.matchType == .exactPhone }
    }

    var emailGroups: [DuplicateGroup] {
        viewModel.duplicateGroups.filter { $0.matchType == .exactEmail }
    }

    var similarGroups: [DuplicateGroup] {
        viewModel.duplicateGroups.filter { $0.matchType == .similar }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView(viewModel.loadingMessage)
                } else if viewModel.duplicateGroups.isEmpty {
                    ContentUnavailableView(
                        "No Duplicates Found",
                        systemImage: "checkmark.circle.fill",
                        description: Text("Your contacts look clean!")
                    )
                } else {
                    List {
                        // Same Phone Section
                        if !phoneGroups.isEmpty {
                            Section {
                                ForEach(phoneGroups) { group in
                                    DuplicateGroupRow(group: group)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedGroup = group
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button("Not Duplicate") {
                                                viewModel.dismissDuplicateGroup(group)
                                            }
                                            .tint(.orange)
                                        }
                                }
                            } header: {
                                HStack {
                                    Image(systemName: "phone.fill")
                                        .foregroundColor(.green)
                                    Text("Same Phone Number (\(phoneGroups.count))")
                                    Spacer()
                                    Button("Merge All") {
                                        mergeType = .exactPhone
                                        showMergeConfirmation = true
                                    }
                                    .font(.caption)
                                }
                            } footer: {
                                Text("These contacts share the same phone number")
                            }
                        }

                        // Same Email Section
                        if !emailGroups.isEmpty {
                            Section {
                                ForEach(emailGroups) { group in
                                    DuplicateGroupRow(group: group)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedGroup = group
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button("Not Duplicate") {
                                                viewModel.dismissDuplicateGroup(group)
                                            }
                                            .tint(.orange)
                                        }
                                }
                            } header: {
                                HStack {
                                    Image(systemName: "envelope.fill")
                                        .foregroundColor(.blue)
                                    Text("Same Email Address (\(emailGroups.count))")
                                    Spacer()
                                    Button("Merge All") {
                                        mergeType = .exactEmail
                                        showMergeConfirmation = true
                                    }
                                    .font(.caption)
                                }
                            } footer: {
                                Text("These contacts share the same email address")
                            }
                        }

                        // Similar Names Section
                        if !similarGroups.isEmpty {
                            Section {
                                ForEach(similarGroups) { group in
                                    DuplicateGroupRow(group: group)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedGroup = group
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button("Not Duplicate") {
                                                viewModel.dismissDuplicateGroup(group)
                                            }
                                            .tint(.orange)
                                        }
                                }
                            } header: {
                                HStack {
                                    Image(systemName: "person.2.fill")
                                        .foregroundColor(.orange)
                                    Text("Similar Names (\(similarGroups.count))")
                                    Spacer()
                                    Button("Merge All") {
                                        mergeType = .similar
                                        showMergeConfirmation = true
                                    }
                                    .font(.caption)
                                }
                            } footer: {
                                Text("These contacts have nearly identical names - review carefully")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Duplicates")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.findDuplicates()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .sheet(item: $selectedGroup) { group in
                MergeContactView(group: group)
            }
            .alert(mergeAlertTitle, isPresented: $showMergeConfirmation) {
                Button("Cancel", role: .cancel) { mergeType = nil }
                Button("Merge All", role: .destructive) {
                    Task {
                        await viewModel.mergeGroups(ofType: mergeType)
                        mergeType = nil
                    }
                }
            } message: {
                Text(mergeAlertMessage)
            }
            .alert("Success", isPresented: .constant(viewModel.successMessage != nil && !viewModel.isLoading)) {
                Button("OK") { viewModel.clearMessages() }
            } message: {
                Text(viewModel.successMessage ?? "")
            }
        }
    }

    var mergeAlertTitle: String {
        guard let type = mergeType else { return "Merge Duplicates?" }
        switch type {
        case .exactPhone: return "Merge Phone Duplicates?"
        case .exactEmail: return "Merge Email Duplicates?"
        case .similar: return "Merge Similar Names?"
        }
    }

    var mergeAlertMessage: String {
        guard let type = mergeType else { return "" }
        let count: Int
        let description: String
        switch type {
        case .exactPhone:
            count = phoneGroups.count
            description = "contacts with matching phone numbers"
        case .exactEmail:
            count = emailGroups.count
            description = "contacts with matching email addresses"
        case .similar:
            count = similarGroups.count
            description = "contacts with similar names"
        }
        return "This will merge \(count) groups of \(description). This syncs to Apple Contacts and cannot be undone."
    }
}

struct DuplicateGroupRow: View {
    let group: DuplicateGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: -8) {
                ForEach(group.contacts.prefix(4)) { contact in
                    ContactAvatarView(contact: contact, size: 36)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                }
                if group.contacts.count > 4 {
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.3))
                        Text("+\(group.contacts.count - 4)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(group.contacts.prefix(3)) { contact in
                    Text(contact.displayName)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                if group.contacts.count > 3 {
                    Text("and \(group.contacts.count - 3) more...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct MatchTypeBadge: View {
    let matchType: DuplicateMatchType

    var color: Color {
        switch matchType {
        case .exactEmail: return .blue
        case .exactPhone: return .green
        case .similar: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: matchType.icon)
                .font(.caption2)
            Text(matchType.rawValue)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.2))
        .foregroundColor(color)
        .clipShape(Capsule())
    }
}

#Preview {
    DuplicatesView()
        .environmentObject(ContactViewModel())
}
