import CoreData
import Foundation

class CoreDataManager {
    static let shared = CoreDataManager()

    @Published var databaseError: String?
    private var _persistentContainer: NSPersistentContainer?

    var persistentContainer: NSPersistentContainer {
        if let container = _persistentContainer {
            return container
        }

        let container = NSPersistentContainer(name: "ContactDedup")
        container.loadPersistentStores { [weak self] _, error in
            if let error = error {
                print("Core Data failed to load: \(error)")
                self?.databaseError = "Database corrupted. Please reset in Settings."
                // Try to recover by deleting and recreating
                self?.handlePersistentStoreError()
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        _persistentContainer = container
        return container
    }

    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    private init() {}

    // MARK: - Database Recovery

    private func handlePersistentStoreError() {
        // This will be called if loading fails - user can manually reset via Settings
        print("Database needs recovery - user should reset via Settings")
    }

    func resetDatabase() -> Bool {
        // Get the store URL
        guard let storeURL = _persistentContainer?.persistentStoreDescriptions.first?.url ??
              FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("ContactDedup.sqlite") else {
            return false
        }

        // Remove the persistent store
        if let container = _persistentContainer {
            for store in container.persistentStoreCoordinator.persistentStores {
                do {
                    try container.persistentStoreCoordinator.remove(store)
                } catch {
                    print("Failed to remove store: \(error)")
                }
            }
        }

        // Delete all database files
        let fileManager = FileManager.default
        let storePath = storeURL.path
        let walPath = storePath + "-wal"
        let shmPath = storePath + "-shm"

        do {
            if fileManager.fileExists(atPath: storePath) {
                try fileManager.removeItem(atPath: storePath)
            }
            if fileManager.fileExists(atPath: walPath) {
                try fileManager.removeItem(atPath: walPath)
            }
            if fileManager.fileExists(atPath: shmPath) {
                try fileManager.removeItem(atPath: shmPath)
            }
        } catch {
            print("Failed to delete database files: \(error)")
            return false
        }

        // Reset the container so it gets recreated
        _persistentContainer = nil
        databaseError = nil

        // Force recreation
        _ = persistentContainer

        return true
    }

    func getDatabaseSize() -> String {
        guard let storeURL = _persistentContainer?.persistentStoreDescriptions.first?.url else {
            return "Unknown"
        }

        let fileManager = FileManager.default
        var totalSize: Int64 = 0

        let paths = [
            storeURL.path,
            storeURL.path + "-wal",
            storeURL.path + "-shm"
        ]

        for path in paths {
            if let attrs = try? fileManager.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                totalSize += size
            }
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }

    func saveContext() {
        let context = viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Error saving context: \(error)")
            }
        }
    }

    func saveContact(_ contact: ContactData) {
        let fetchRequest: NSFetchRequest<ContactEntity> = ContactEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", contact.id as CVarArg)

        do {
            let results = try viewContext.fetch(fetchRequest)
            let entity: ContactEntity
            if let existing = results.first {
                entity = existing
            } else {
                entity = ContactEntity(context: viewContext)
            }
            entity.update(from: contact)
            saveContext()
        } catch {
            print("Error saving contact: \(error)")
        }
    }

    func saveContacts(_ contacts: [ContactData]) {
        // Batch save - only save once at the end
        let existingIds = Set(fetchAllContactIds())

        for contact in contacts {
            let entity: ContactEntity
            if existingIds.contains(contact.id) {
                let fetchRequest: NSFetchRequest<ContactEntity> = ContactEntity.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", contact.id as CVarArg)
                fetchRequest.fetchLimit = 1
                if let existing = try? viewContext.fetch(fetchRequest).first {
                    entity = existing
                } else {
                    entity = ContactEntity(context: viewContext)
                }
            } else {
                entity = ContactEntity(context: viewContext)
            }
            entity.update(from: contact)
        }

        // Single save at the end
        saveContext()
    }

    private func fetchAllContactIds() -> [UUID] {
        let fetchRequest: NSFetchRequest<ContactEntity> = ContactEntity.fetchRequest()
        fetchRequest.propertiesToFetch = ["id"]

        do {
            let entities = try viewContext.fetch(fetchRequest)
            return entities.compactMap { $0.id }
        } catch {
            return []
        }
    }

    func fetchAllContacts() -> [ContactData] {
        let fetchRequest: NSFetchRequest<ContactEntity> = ContactEntity.fetchRequest()
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ContactEntity.lastName, ascending: true),
            NSSortDescriptor(keyPath: \ContactEntity.firstName, ascending: true)
        ]

        do {
            let entities = try viewContext.fetch(fetchRequest)
            return entities.map { $0.toContactData() }
        } catch {
            print("Error fetching contacts: \(error)")
            return []
        }
    }

    func fetchIncompleteContacts() -> [ContactData] {
        let fetchRequest: NSFetchRequest<ContactEntity> = ContactEntity.fetchRequest()

        do {
            let entities = try viewContext.fetch(fetchRequest)
            return entities
                .map { $0.toContactData() }
                .filter { $0.isIncomplete }
        } catch {
            print("Error fetching incomplete contacts: \(error)")
            return []
        }
    }

    func deleteContact(id: UUID) {
        let fetchRequest: NSFetchRequest<ContactEntity> = ContactEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        do {
            let results = try viewContext.fetch(fetchRequest)
            results.forEach { viewContext.delete($0) }
            saveContext()
        } catch {
            print("Error deleting contact: \(error)")
        }
    }

    func deleteContacts(ids: [UUID]) {
        let fetchRequest: NSFetchRequest<ContactEntity> = ContactEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

        do {
            let results = try viewContext.fetch(fetchRequest)
            results.forEach { viewContext.delete($0) }
            saveContext()
        } catch {
            print("Error deleting contacts: \(error)")
        }
    }

    func contactExists(appleIdentifier: String) -> Bool {
        let fetchRequest: NSFetchRequest<ContactEntity> = ContactEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "appleIdentifier == %@", appleIdentifier)
        fetchRequest.fetchLimit = 1

        do {
            let count = try viewContext.count(for: fetchRequest)
            return count > 0
        } catch {
            return false
        }
    }

    func contactExists(googleIdentifier: String) -> Bool {
        let fetchRequest: NSFetchRequest<ContactEntity> = ContactEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "googleIdentifier == %@", googleIdentifier)
        fetchRequest.fetchLimit = 1

        do {
            let count = try viewContext.count(for: fetchRequest)
            return count > 0
        } catch {
            return false
        }
    }

    func findSimilarContact(to contact: ContactData) -> ContactData? {
        let allContacts = fetchAllContacts()
        let detector = DuplicateDetector()

        for existing in allContacts {
            if existing.id == contact.id { continue }
            let score = detector.calculateSimilarity(contact1: contact, contact2: existing)
            if score > 0.8 {
                return existing
            }
        }
        return nil
    }

    func clearAllContacts() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = ContactEntity.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

        do {
            try persistentContainer.persistentStoreCoordinator.execute(deleteRequest, with: viewContext)
            viewContext.reset()
        } catch {
            print("Error clearing contacts: \(error)")
        }
    }
}

// MARK: - ContactEntity Extensions

extension ContactEntity {
    func toContactData() -> ContactData {
        ContactData(
            id: id ?? UUID(),
            firstName: firstName ?? "",
            lastName: lastName ?? "",
            company: company ?? "",
            emails: (emails as? [String]) ?? [],
            phoneNumbers: (phoneNumbers as? [String]) ?? [],
            addresses: (addresses as? [String]) ?? [],
            notes: notes ?? "",
            imageData: imageData,
            source: ContactSource(rawValue: source ?? "apple") ?? .apple,
            appleIdentifier: appleIdentifier,
            googleIdentifier: googleIdentifier,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date()
        )
    }

    func update(from contact: ContactData) {
        self.id = contact.id
        self.firstName = contact.firstName
        self.lastName = contact.lastName
        self.company = contact.company
        self.emails = contact.emails as NSArray
        self.phoneNumbers = contact.phoneNumbers as NSArray
        self.addresses = contact.addresses as NSArray
        self.notes = contact.notes
        self.imageData = contact.imageData
        self.source = contact.source.rawValue
        self.appleIdentifier = contact.appleIdentifier
        self.googleIdentifier = contact.googleIdentifier
        self.createdAt = contact.createdAt
        self.updatedAt = Date()
    }
}
