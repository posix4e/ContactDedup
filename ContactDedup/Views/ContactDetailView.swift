import SwiftUI

struct ContactDetailView: View {
    @EnvironmentObject var viewModel: ContactViewModel
    @Environment(\.dismiss) var dismiss

    let contact: ContactData
    @State private var editedContact: ContactData
    @State private var isEditing = false
    @State private var showDeleteConfirmation = false

    init(contact: ContactData) {
        self.contact = contact
        self._editedContact = State(initialValue: contact)
    }

    var body: some View {
        NavigationStack {
            List {
                // Avatar and Name Section
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ContactAvatarView(contact: editedContact, size: 100)

                            if isEditing {
                                VStack(spacing: 8) {
                                    TextField("First Name", text: $editedContact.firstName)
                                        .textFieldStyle(.roundedBorder)
                                    TextField("Last Name", text: $editedContact.lastName)
                                        .textFieldStyle(.roundedBorder)
                                }
                                .frame(maxWidth: 250)
                            } else {
                                Text(editedContact.displayName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }

                            if editedContact.isIncomplete {
                                Label("Incomplete - No contact info", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                // Company
                Section("Company") {
                    if isEditing {
                        TextField("Company", text: $editedContact.company)
                    } else if !editedContact.company.isEmpty {
                        Text(editedContact.company)
                    } else {
                        Text("No company")
                            .foregroundColor(.secondary)
                    }
                }

                // Emails
                Section("Email Addresses") {
                    if isEditing {
                        ForEach(editedContact.emails.indices, id: \.self) { index in
                            HStack {
                                TextField("Email", text: $editedContact.emails[index])
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                Button {
                                    editedContact.emails.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        Button {
                            editedContact.emails.append("")
                        } label: {
                            Label("Add Email", systemImage: "plus.circle.fill")
                        }
                    } else if editedContact.emails.isEmpty {
                        Text("No email addresses")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(editedContact.emails, id: \.self) { email in
                            HStack {
                                Image(systemName: "envelope.fill")
                                    .foregroundColor(.accentColor)
                                Text(email)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = email
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                            }
                        }
                    }
                }

                // Phone Numbers
                Section("Phone Numbers") {
                    if isEditing {
                        ForEach(editedContact.phoneNumbers.indices, id: \.self) { index in
                            HStack {
                                TextField("Phone", text: $editedContact.phoneNumbers[index])
                                    .keyboardType(.phonePad)
                                Button {
                                    editedContact.phoneNumbers.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        Button {
                            editedContact.phoneNumbers.append("")
                        } label: {
                            Label("Add Phone", systemImage: "plus.circle.fill")
                        }
                    } else if editedContact.phoneNumbers.isEmpty {
                        Text("No phone numbers")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(editedContact.phoneNumbers, id: \.self) { phone in
                            HStack {
                                Image(systemName: "phone.fill")
                                    .foregroundColor(.green)
                                Text(phone)
                                Spacer()
                                Button {
                                    if let url = URL(string: "tel:\(phone)") {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    Image(systemName: "phone.arrow.up.right")
                                }
                            }
                        }
                    }
                }

                // Addresses
                if !editedContact.addresses.isEmpty || isEditing {
                    Section("Addresses") {
                        if isEditing {
                            ForEach(editedContact.addresses.indices, id: \.self) { index in
                                HStack {
                                    TextField("Address", text: $editedContact.addresses[index])
                                    Button {
                                        editedContact.addresses.remove(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                            Button {
                                editedContact.addresses.append("")
                            } label: {
                                Label("Add Address", systemImage: "plus.circle.fill")
                            }
                        } else {
                            ForEach(editedContact.addresses, id: \.self) { address in
                                HStack {
                                    Image(systemName: "map.fill")
                                        .foregroundColor(.orange)
                                    Text(address)
                                }
                            }
                        }
                    }
                }

                // Notes
                if !editedContact.notes.isEmpty || isEditing {
                    Section("Notes") {
                        if isEditing {
                            TextEditor(text: $editedContact.notes)
                                .frame(minHeight: 100)
                        } else {
                            Text(editedContact.notes)
                        }
                    }
                }

                // Metadata
                Section("Info") {
                    HStack {
                        Text("Source")
                        Spacer()
                        Text(editedContact.source.rawValue.capitalized)
                            .foregroundColor(.secondary)
                    }
                    if let appleId = editedContact.appleIdentifier {
                        HStack {
                            Text("Apple ID")
                            Spacer()
                            Text(appleId.prefix(8) + "...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Delete Button
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Contact", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Contact" : "Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEditing ? "Cancel" : "Done") {
                        if isEditing {
                            editedContact = contact
                            isEditing = false
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isEditing ? "Save" : "Edit") {
                        if isEditing {
                            // Clean up empty entries
                            editedContact.emails = editedContact.emails.filter { !$0.isEmpty }
                            editedContact.phoneNumbers = editedContact.phoneNumbers.filter { !$0.isEmpty }
                            editedContact.addresses = editedContact.addresses.filter { !$0.isEmpty }

                            Task {
                                await viewModel.updateContact(editedContact)
                                isEditing = false
                            }
                        } else {
                            isEditing = true
                        }
                    }
                    .fontWeight(isEditing ? .semibold : .regular)
                }
            }
            .alert("Delete Contact?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteContact(editedContact)
                        dismiss()
                    }
                }
            } message: {
                Text("This will permanently delete this contact from Apple Contacts. This cannot be undone.")
            }
        }
    }
}

#Preview {
    ContactDetailView(contact: ContactData(
        firstName: "John",
        lastName: "Doe",
        company: "Acme Inc",
        emails: ["john@example.com", "johndoe@work.com"],
        phoneNumbers: ["555-1234", "555-5678"]
    ))
    .environmentObject(ContactViewModel())
}
