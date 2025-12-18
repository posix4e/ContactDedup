import SwiftUI

enum ContactGrouping: String, CaseIterable {
    case none = "None"
    case areaCode = "Area Code"
    case emailDomain = "Email Domain"
}

struct ContactsListView: View {
    @EnvironmentObject var viewModel: ContactViewModel
    @State private var searchText = ""
    @State private var selectedContact: ContactData?
    @State private var grouping: ContactGrouping = .none
    @State private var selectedGroup: String?  // nil means show all groups

    // Common public email domains to ignore when grouping
    private static let publicEmailDomains: Set<String> = [
        "gmail.com", "googlemail.com", "yahoo.com", "yahoo.co.uk", "hotmail.com",
        "outlook.com", "live.com", "msn.com", "icloud.com", "me.com", "mac.com",
        "aol.com", "protonmail.com", "proton.me", "mail.com", "zoho.com",
        "yandex.com", "gmx.com", "gmx.net", "fastmail.com", "tutanota.com"
    ]

    var filteredContacts: [ContactData] {
        if searchText.isEmpty {
            return viewModel.contacts
        }
        return viewModel.contacts.filter { contact in
            contact.fullName.localizedCaseInsensitiveContains(searchText) ||
            contact.emails.contains { $0.localizedCaseInsensitiveContains(searchText) } ||
            contact.phoneNumbers.contains { $0.localizedCaseInsensitiveContains(searchText) } ||
            contact.company.localizedCaseInsensitiveContains(searchText)
        }
    }

    var allGroups: [(String, [ContactData])] {
        switch grouping {
        case .none:
            return [("All Contacts", filteredContacts.sorted { $0.displayName < $1.displayName })]
        case .areaCode:
            return groupByAreaCode(filteredContacts)
        case .emailDomain:
            return groupByEmailDomain(filteredContacts)
        }
    }

    var availableGroupNames: [String] {
        allGroups.map { $0.0 }
    }

    var groupedContacts: [(String, [ContactData])] {
        if let selected = selectedGroup {
            return allGroups.filter { $0.0 == selected }
        }
        return allGroups
    }

    private func groupByAreaCode(_ contacts: [ContactData]) -> [(String, [ContactData])] {
        var groups: [String: [ContactData]] = [:]

        for contact in contacts {
            let areaCode = extractAreaCode(from: contact.phoneNumbers)
            groups[areaCode, default: []].append(contact)
        }

        return groups.sorted { $0.key < $1.key }.map { ($0.key, $0.value.sorted { $0.displayName < $1.displayName }) }
    }

    private func extractAreaCode(from phoneNumbers: [String]) -> String {
        for phone in phoneNumbers {
            let digits = phone.filter { $0.isNumber }
            // US/Canada format: assume 10+ digits, area code is first 3 after country code
            if digits.count >= 10 {
                let hasCountryCode = digits.count == 11 && digits.hasPrefix("1")
                let start = hasCountryCode ? digits.index(digits.startIndex, offsetBy: 1) : digits.startIndex
                let end = digits.index(start, offsetBy: 3)
                return "(\(String(digits[start..<end])))"
            }
        }
        return "(No Phone)"
    }

    private func groupByEmailDomain(_ contacts: [ContactData]) -> [(String, [ContactData])] {
        var groups: [String: [ContactData]] = [:]

        for contact in contacts {
            let domain = extractOrganizationDomain(from: contact.emails)
            groups[domain, default: []].append(contact)
        }

        return groups.sorted { $0.key < $1.key }.map { ($0.key, $0.value.sorted { $0.displayName < $1.displayName }) }
    }

    private func extractOrganizationDomain(from emails: [String]) -> String {
        for email in emails {
            guard let atIndex = email.lastIndex(of: "@") else { continue }
            let domain = String(email[email.index(after: atIndex)...]).lowercased()

            // Skip public email domains
            if Self.publicEmailDomains.contains(domain) {
                continue
            }

            // Return the organization domain
            return domain
        }
        return "(Personal/No Email)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.contacts.isEmpty {
                    ProgressView(viewModel.loadingMessage)
                } else if viewModel.contacts.isEmpty {
                    ContentUnavailableView(
                        "No Contacts",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Import contacts from Apple or Google to get started.")
                    )
                } else {
                    List {
                        ForEach(groupedContacts, id: \.0) { group in
                            Section(header: Text("\(group.0) (\(group.1.count))")) {
                                ForEach(group.1) { contact in
                                    ContactRowView(contact: contact)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedContact = contact
                                        }
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search contacts")
                }
            }
            .navigationTitle(selectedGroup ?? "Contacts (\(viewModel.contacts.count))")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section("Group By") {
                            Picker("Group By", selection: $grouping) {
                                ForEach(ContactGrouping.allCases, id: \.self) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                        }

                        if grouping != .none {
                            Section("Filter Group") {
                                Button("Show All Groups") {
                                    selectedGroup = nil
                                }

                                ForEach(availableGroupNames, id: \.self) { groupName in
                                    Button {
                                        selectedGroup = groupName
                                    } label: {
                                        HStack {
                                            Text(groupName)
                                            if selectedGroup == groupName {
                                                Spacer()
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        let iconName = grouping == .none
                            ? "line.3.horizontal.decrease.circle"
                            : "line.3.horizontal.decrease.circle.fill"
                        Image(systemName: iconName)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.loadContacts()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .onChange(of: grouping) { _, _ in
                selectedGroup = nil  // Reset filter when changing grouping mode
            }
            .sheet(item: $selectedContact) { contact in
                ContactDetailView(contact: contact)
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.clearMessages() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}

struct ContactRowView: View {
    let contact: ContactData

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

                if let email = contact.emails.first {
                    Text(email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let phone = contact.phoneNumbers.first {
                    Text(phone)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if contact.isIncomplete {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            }

            sourceIcon
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    var sourceIcon: some View {
        switch contact.source {
        case .apple:
            Image(systemName: "apple.logo")
                .foregroundColor(.secondary)
                .font(.caption)
        case .google:
            Image(systemName: "g.circle.fill")
                .foregroundColor(.secondary)
                .font(.caption)
        case .linkedin:
            Image(systemName: "link.circle.fill")
                .foregroundColor(.secondary)
                .font(.caption)
        case .manual:
            Image(systemName: "hand.draw.fill")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }
}

struct ContactAvatarView: View {
    let contact: ContactData
    let size: CGFloat

    var body: some View {
        Group {
            if let imageData = contact.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                    Text(initials)
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundColor(.accentColor)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    var initials: String {
        let first = contact.firstName.first.map(String.init) ?? ""
        let last = contact.lastName.first.map(String.init) ?? ""
        let result = first + last
        return result.isEmpty ? "?" : result.uppercased()
    }
}

#Preview {
    ContactsListView()
        .environmentObject(ContactViewModel())
}
