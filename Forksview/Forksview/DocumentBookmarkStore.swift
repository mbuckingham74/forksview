import Foundation

// MARK: - Archive Envelope (Milestone 8)

struct BookmarkArchive: Codable, Equatable, Sendable {
    let schemaVersion: Int
    var documents: [PersistedDocumentBookmarks]

    static let currentVersion = 1

    init(schemaVersion: Int = currentVersion, documents: [PersistedDocumentBookmarks] = []) {
        self.schemaVersion = schemaVersion
        self.documents = documents
    }
}

struct PersistedDocumentBookmarks: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var fileBookmarkData: Data
    var lastKnownPath: String
    var bookmarks: [DocumentBookmark]

    init(id: UUID = UUID(), fileBookmarkData: Data, lastKnownPath: String, bookmarks: [DocumentBookmark]) {
        self.id = id
        self.fileBookmarkData = fileBookmarkData
        self.lastKnownPath = lastKnownPath
        self.bookmarks = bookmarks
    }
}

// MARK: - Store

/// Concrete app-owned store for bookmarks.
/// Uses one versioned Codable JSON archive at ~/Library/Application Support/org.mzb74.Forksview/Bookmarks.json
/// Supports injected archive URL for tests and env override for UI tests.
final class DocumentBookmarkStore: @unchecked Sendable {
    static let schemaVersion = 1
    static let envOverrideKey = "FORKSVIEW_BOOKMARK_ARCHIVE_PATH"
    // Also support alternative key for compatibility
    static let envAltKey = "FORKSVIEW_BOOKMARKS_PATH"

    let archiveURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var cachedArchive: BookmarkArchive
    // A malformed or unsupported archive is intentionally session-only. Do not
    // replace the user's original bytes with a newly encoded empty archive.
    private var persistenceDisabled = false

    // MARK: - Init

    init(archiveURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let injected = archiveURL {
            self.archiveURL = injected
        } else if let envPath = DocumentBookmarkStore.resolveEnvOverride() {
            self.archiveURL = URL(fileURLWithPath: envPath)
        } else {
            self.archiveURL = DocumentBookmarkStore.defaultArchiveURL(fileManager: fileManager)
        }
        // Load archive nonfatally. A present-but-invalid archive remains
        // untouched and disables writes for this store instance.
        let archiveExists = fileManager.fileExists(atPath: self.archiveURL.path)
        if let loaded = DocumentBookmarkStore.loadArchive(from: self.archiveURL, fileManager: fileManager) {
            self.cachedArchive = loaded
        } else {
            // Load failed; preserve file but use empty in-memory archive
            self.cachedArchive = BookmarkArchive(schemaVersion: Self.schemaVersion, documents: [])
            self.persistenceDisabled = archiveExists
        }
    }

    // MARK: - Default Location

    static func defaultArchiveURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let dir = base.appendingPathComponent("org.mzb74.Forksview", isDirectory: true)
        return dir.appendingPathComponent("Bookmarks.json", isDirectory: false)
    }

    static func resolveEnvOverride() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let v = env[envOverrideKey], !v.isEmpty { return v }
        if let v = env[envAltKey], !v.isEmpty { return v }
        return nil
    }

    // MARK: - Archive Load / Save

    /// Load archive from URL. Returns nil on failure (and preserves file). Returns empty archive if file doesn't exist.
    static func loadArchive(from url: URL, fileManager: FileManager = .default) -> BookmarkArchive? {
        guard fileManager.fileExists(atPath: url.path) else {
            return BookmarkArchive(schemaVersion: schemaVersion, documents: [])
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let archive = try decoder.decode(BookmarkArchive.self, from: data)
            guard archive.schemaVersion == schemaVersion else {
                // Unsupported schema version: preserve file, fail nonfatally
                fputs("DocumentBookmarkStore: unsupported schemaVersion \(archive.schemaVersion), preserving existing archive at \(url.path)\n", stderr)
                return nil
            }
            return archive
        } catch {
            fputs("DocumentBookmarkStore: failed to load archive at \(url.path): \(error). Preserving file.\n", stderr)
            return nil
        }
    }

    private func reloadIfNeeded() {
        // Used for atomic reload testing; reload from disk nonfatally
        if let loaded = Self.loadArchive(from: archiveURL, fileManager: fileManager) {
            lock.lock()
            cachedArchive = loaded
            persistenceDisabled = false
            lock.unlock()
        } else {
            // Preserve existing cachedArchive if load fails (corrupt)
        }
    }

    /// Atomically write archive to disk. Preserves bad existing file handling.
    private func persistArchive(_ archive: BookmarkArchive) {
        lock.lock()
        cachedArchive = archive
        let shouldPersist = !persistenceDisabled
        lock.unlock()
        guard shouldPersist else { return }
        do {
            let dir = archiveURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(archive)
            // Atomic write via Foundation .atomic option (writes to temp then replace)
            try data.write(to: archiveURL, options: [.atomic])
        } catch {
            fputs("DocumentBookmarkStore: failed to persist archive at \(archiveURL.path): \(error)\n", stderr)
        }
    }

    /// Public reload for test "atomic store reload" verification.
    func reload() {
        reloadIfNeeded()
    }

    /// Expose current archive for testing
    func currentArchive() -> BookmarkArchive {
        lock.lock()
        defer { lock.unlock() }
        return cachedArchive
    }

    // MARK: - URL Bookmark Data Helpers

    static func bookmarkData(for url: URL) throws -> Data {
        // Normal bookmark data, not security scoped
        return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolve bookmark data to URL. Returns nil if cannot resolve. Also reports if stale via out param.
    static func resolveBookmarkData(_ data: Data) -> (url: URL?, isStale: Bool) {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &isStale)
            return (url, isStale)
        } catch {
            return (nil, false)
        }
    }

    // MARK: - Record Lookup

    /// Find persisted record matching given file URL via bookmark resolution.
    /// Also refresh stale bookmark data if needed.
    private func indexOfRecord(matching fileURL: URL, in archive: BookmarkArchive) -> Int? {
        for (idx, record) in archive.documents.enumerated() {
            let resolved = Self.resolveBookmarkData(record.fileBookmarkData)
            if let resolvedURL = resolved.url {
                // Compare via FileManager or URL path normalization? Use resolving + comparing standardized file URLs.
                // URL bookmark data resolves to exact file URL; we can compare via URL equality with standardization.
                if urlsEqual(resolvedURL, fileURL) {
                    return idx
                }
            } else {
                // Fallback: if resolution fails, compare lastKnownPath as diagnostic only, not primary? Spec says don't make path primary. But for finding record when bookmark data stale and file moved, resolvedURL should still succeed via bookmark. If it fails, we don't match by path to avoid attaching to unrelated file. So ignore path fallback for identity.
            }
            // Also check stale refresh: if isStale and resolvedURL equals fileURL, update bookmarkData
        }
        return nil
    }

    private func urlsEqual(_ a: URL, _ b: URL) -> Bool {
        // Use standardized file URLs and compare paths. Also handle file existence? Simpler: compare standardized path.
        let sa = a.standardizedFileURL
        let sb = b.standardizedFileURL
        if sa == sb { return true }
        // Also compare via file resource identifier? Spec says don't use persisted file resource identifiers as sole identity. But we can try to compare inode? We rely on bookmark resolution already.
        return sa.path == sb.path
    }

    /// Find record index by resolving bookmark data, with stale refresh handling.
    func recordIndex(for fileURL: URL) -> Int? {
        lock.lock()
        let archive = cachedArchive
        lock.unlock()
        return indexOfRecord(matching: fileURL, in: archive)
    }

    // MARK: - Public API: Load / Save Bookmarks for File URL

    func loadBookmarks(for fileURL: URL?) -> [DocumentBookmark] {
        guard let fileURL = fileURL else { return [] }
        // Always reload from disk to handle multi-document shared file (each document has its own store instance)
        reloadIfNeeded()
        lock.lock()
        var archive = cachedArchive
        lock.unlock()

        // Try to find record
        if let idx = indexOfRecord(matching: fileURL, in: archive) {
            var record = archive.documents[idx]
            // Check stale and refresh
            let resolved = Self.resolveBookmarkData(record.fileBookmarkData)
            if resolved.isStale, let resolvedURL = resolved.url, urlsEqual(resolvedURL, fileURL) {
                // Refresh bookmark data
                if let freshData = try? Self.bookmarkData(for: fileURL) {
                    record.fileBookmarkData = freshData
                    record.lastKnownPath = fileURL.path
                    archive.documents[idx] = record
                    persistArchive(archive)
                }
                return record.bookmarks
            } else if resolved.isStale {
                // Stale but still points to same file? Already handled. If stale but not equal, still stale but refresh.
                if let freshData = try? Self.bookmarkData(for: fileURL) {
                    record.fileBookmarkData = freshData
                    record.lastKnownPath = fileURL.path
                    archive.documents[idx] = record
                    persistArchive(archive)
                }
            }
            // Also update lastKnownPath if path changed due to rename/move that still resolved via bookmark (path differs)
            if record.lastKnownPath != fileURL.path {
                record.lastKnownPath = fileURL.path
                // Refresh bookmark data as well since path changed
                if let freshData = try? Self.bookmarkData(for: fileURL) {
                    record.fileBookmarkData = freshData
                }
                archive.documents[idx] = record
                persistArchive(archive)
            }
            return record.bookmarks
        } else {
            // Check if any record's bookmark data resolves to this URL but via stale path? Already checked via indexOfRecord.
            // No record: return empty, but don't create until save.
            return []
        }
    }

    func saveBookmarks(_ bookmarks: [DocumentBookmark], for fileURL: URL) {
        // Upsert record for fileURL – reload first for multi-document shared file
        reloadIfNeeded()
        lock.lock()
        var archive = cachedArchive
        lock.unlock()

        if let idx = indexOfRecord(matching: fileURL, in: archive) {
            // Update existing
            var record = archive.documents[idx]
            let pathChanged = record.lastKnownPath != fileURL.path
            record.bookmarks = bookmarks
            record.lastKnownPath = fileURL.path
            // Refresh bookmark data if needed or just update
            if let freshData = try? Self.bookmarkData(for: fileURL) {
                // Check if existing data stale
                let resolved = Self.resolveBookmarkData(record.fileBookmarkData)
                if resolved.isStale {
                    record.fileBookmarkData = freshData
                } else {
                    // Also update if file moved? For simplicity, update lastKnownPath and keep bookmarkData unless stale
                    // But to ensure rename/move persists, we update bookmarkData to fresh if path changed
                    if pathChanged {
                        record.fileBookmarkData = freshData
                    }
                }
            }
            archive.documents[idx] = record
            persistArchive(archive)
        } else {
            // Create new record
            let data: Data
            do {
                data = try Self.bookmarkData(for: fileURL)
            } catch {
                // If bookmark data fails (e.g., file doesn't exist yet? Should exist for file-backed doc), still create with empty data? But spec says create/resolve normal URL bookmark. If fails, create empty data and still store? Better to log and return.
                fputs("DocumentBookmarkStore: failed to create bookmark data for \(fileURL.path): \(error)\n", stderr)
                return
            }
            let newRecord = PersistedDocumentBookmarks(
                id: UUID(),
                fileBookmarkData: data,
                lastKnownPath: fileURL.path,
                bookmarks: bookmarks
            )
            archive.documents.append(newRecord)
            persistArchive(archive)
        }
    }

    // MARK: - Save As Clone Semantics

    /// After successful Save As, original file keeps its existing bookmark record; destination gets cloned bookmark set; active document becomes bound to destination.
    func handleSaveAs(from sourceURL: URL, to destinationURL: URL) {
        // Load source bookmarks (this reloads)
        let sourceBookmarks = loadBookmarks(for: sourceURL)
        // Check if destination already has record (e.g., overwriting) -> we will overwrite its bookmarks with clone? Spec: destination gets cloned bookmark set. So if dest exists, replace its bookmarks with source's clone.
        reloadIfNeeded()
        lock.lock()
        var archive = cachedArchive
        lock.unlock()

        // Find dest index
        if let destIdx = indexOfRecord(matching: destinationURL, in: archive) {
            var destRecord = archive.documents[destIdx]
            destRecord.bookmarks = sourceBookmarks
            destRecord.lastKnownPath = destinationURL.path
            if let freshData = try? Self.bookmarkData(for: destinationURL) {
                destRecord.fileBookmarkData = freshData
            }
            archive.documents[destIdx] = destRecord
            persistArchive(archive)
        } else {
            // Create new record for destination with cloned bookmarks
            let data: Data
            do {
                data = try Self.bookmarkData(for: destinationURL)
            } catch {
                fputs("DocumentBookmarkStore: failed to create bookmark data for SaveAs dest \(destinationURL.path): \(error)\n", stderr)
                return
            }
            let newRecord = PersistedDocumentBookmarks(
                id: UUID(),
                fileBookmarkData: data,
                lastKnownPath: destinationURL.path,
                bookmarks: sourceBookmarks
            )
            archive.documents.append(newRecord)
            persistArchive(archive)
        }
        // Source record remains unchanged (do not move/delete)
    }

    /// Clone bookmarks from source to destination with provided bookmarks (alternative for untitled -> saved)
    func bindAndPersistBookmarks(_ bookmarks: [DocumentBookmark], for fileURL: URL) {
        saveBookmarks(bookmarks, for: fileURL)
    }

    // MARK: - Isolation Helpers

    /// Separate document records remain isolated: already via fileURL identity.

    // MARK: - Utility for Tests: Unresolvable record cannot attach to unrelated file

    func containsRecord(for fileURL: URL) -> Bool {
        return recordIndex(for: fileURL) != nil
    }

    // For testing version round-trip
    static func archiveRoundtrip(_ archive: BookmarkArchive) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(archive)
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(BookmarkArchive.self, from: data)
            return decoded == archive
        } catch {
            return false
        }
    }

    // MARK: - Shared instance for production (optional)

    static let shared = DocumentBookmarkStore()

    // MARK: - Delete / Diagnostic

    func allRecords() -> [PersistedDocumentBookmarks] {
        lock.lock()
        defer { lock.unlock() }
        return cachedArchive.documents
    }

    /// Do not automatically delete persisted records merely because resolution temporarily fails. So no auto-clean.

    /// For tests: clear all (remove file)
    func clearForTests() {
        lock.lock()
        cachedArchive = BookmarkArchive(schemaVersion: Self.schemaVersion, documents: [])
        persistenceDisabled = false
        lock.unlock()
        // Don't delete file if it's the real Application Support? For test injected URL, safe to delete.
        try? fileManager.removeItem(at: archiveURL)
        // Re-persist empty? Only if needed? Keep file removed for test.
    }
}
