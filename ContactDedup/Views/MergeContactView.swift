import SwiftUI

struct MergeContactView: View {
    @EnvironmentObject var viewModel: ContactViewModel
    @Environment(\.dismiss) var dismiss

    let group: DuplicateGroup
    @State private var selectedPrimaryId: UUID?
    @State private var showConfirmation = false

    var primaryContact: ContactData? {
        guard let id = selectedPrimaryId else { return group.contacts.first }
        return group.contacts.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.accentColor)

                        Text("Merge \(group.contacts.count) Contacts")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Select which contact to keep as primary. Information from other contacts will be merged into it.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top)

                    // Match Type
                    HStack {
                        Text("Match Type:")
                        Spacer()
                        MatchTypeBadge(matchType: group.matchType)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Contact Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Select Primary Contact")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(group.contacts) { contact in
                            ContactSelectionCard(
                                contact: contact,
                                isSelected: (selectedPrimaryId ?? group.contacts.first?.id) == contact.id
                            )
                            .onTapGesture {
                                selectedPrimaryId = contact.id
                            }
                        }
                    }

                    // Merge Preview
                    if let primary = primaryContact {
                        MergePreviewSection(primary: primary, others: group.contacts.filter { $0.id != primary.id })
                    }

                    // Not a Duplicate Button
                    Button {
                        viewModel.dismissDuplicateGroup(group)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle")
                            Text("Not a Duplicate")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .foregroundColor(.secondary)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 100)
                }
            }
            .navigationTitle("Merge Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge") {
                        showConfirmation = true
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Merge Contacts?", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Merge", role: .destructive) {
                    Task {
                        await viewModel.mergeContacts(group, keepingPrimary: selectedPrimaryId ?? group.contacts.first!.id)
                        dismiss()
                    }
                }
            } message: {
                Text("This will merge all contacts into the selected primary contact. Duplicate contacts will be deleted from Apple Contacts. This cannot be undone.")
            }
        }
    }
}

struct ContactSelectionCard: View {
    let contact: ContactData
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatarView(contact: contact, size: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.displayName)
                    .font(.headline)

                if !contact.company.isEmpty {
                    Text(contact.company)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    if !contact.emails.isEmpty {
                        Label("\(contact.emails.count)", systemImage: "envelope.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if !contact.phoneNumbers.isEmpty {
                        Label("\(contact.phoneNumbers.count)", systemImage: "phone.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            } else {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .padding(.horizontal)
    }
}

struct MergePreviewSection: View {
    let primary: ContactData
    let others: [ContactData]

    var mergedEmails: [String] {
        var emails = primary.emails
        for other in others {
            for email in other.emails where !emails.contains(email) {
                emails.append(email)
            }
        }
        return emails
    }

    var mergedPhones: [String] {
        var phones = primary.phoneNumbers
        for other in others {
            for phone in other.phoneNumbers where !phones.contains(phone) {
                phones.append(phone)
            }
        }
        return phones
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Merged Result Preview")
                .font(.headline)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 16) {
                // Name
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(.secondary)
                        .frame(width: 24)
                    Text(primary.displayName)
                }

                // Emails
                if !mergedEmails.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text("Emails (\(mergedEmails.count))")
                                .foregroundColor(.secondary)
                        }
                        ForEach(mergedEmails, id: \.self) { email in
                            Text(email)
                                .padding(.leading, 32)
                                .font(.subheadline)
                        }
                    }
                }

                // Phones
                if !mergedPhones.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "phone.fill")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text("Phone Numbers (\(mergedPhones.count))")
                                .foregroundColor(.secondary)
                        }
                        ForEach(mergedPhones, id: \.self) { phone in
                            Text(phone)
                                .padding(.leading, 32)
                                .font(.subheadline)
                        }
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
}

#Preview {
    let contacts = [
        ContactData(firstName: "John", lastName: "Doe", emails: ["john@email.com"], phoneNumbers: ["555-1234"]),
        ContactData(firstName: "John", lastName: "D.", emails: ["johnd@work.com"], phoneNumbers: ["555-5678"])
    ]
    MergeContactView(group: DuplicateGroup(contacts: contacts, matchType: .exactEmail, nameSimilarity: 0.85, additionalScores: [:]))
        .environmentObject(ContactViewModel())
}
