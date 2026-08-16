import Foundation
import GRDB

extension SQLiteHistoryStore {
    struct StoredItem {
        let item: ClipboardItem
        let filePaths: [String]
        let richTextRTFBase64: String?
        let richTextHTML: String?
        let pasteboardRepresentations: [ClipboardPasteboardRepresentation]
        let protectedPayload: Data?
        let protectedPayloadDigest: String?
    }

    func loadItems(db: Database) throws -> [ClipboardItem] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM items
                ORDER BY is_pinned DESC, pinned_order IS NULL, pinned_order, created_at DESC
                """
        )
        return try rows.compactMap { row in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            let kindRaw: String = row["kind"]
            let kind = ContentKind(rawValue: kindRaw) ?? .text
            let tags = try tags(for: id, db: db)
            let isProtected = (row["is_protected"] as Int? ?? 0) != 0
            if isProtected {
                if let encryptedPayload: Data = row["protected_payload"],
                   let plaintext = try? protectedHistoryVault.decrypt(encryptedPayload),
                   var item = try? JSONDecoder().decode(ClipboardItem.self, from: plaintext) {
                    item.protectionState = .unlocked
                    item.isPinned = (row["is_pinned"] as Int) != 0
                    item.pinnedOrder = row["pinned_order"]
                    item.tags = tags.isEmpty ? nil : tags
                    let metadataVersion = row["protected_metadata_version"] as Int? ?? 0
                    if metadataVersion > 0 {
                        item.userTitle = row["user_title"]
                        item.userNote = row["user_note"]
                    } else {
                        // Schema v6 kept these labels only inside the encrypted
                        // payload. Promote them on the first successful unlock.
                        try db.execute(
                            sql: """
                                UPDATE items SET
                                    user_title = ?, user_note = ?,
                                    protected_metadata_version = 1
                                WHERE id = ?
                                """,
                            arguments: [
                                item.userTitle,
                                item.userNote,
                                id.uuidString,
                            ]
                        )
                        try replaceSearchIndexEntry(
                            itemID: id,
                            body: Self.protectedMetadataSearchBody(for: item),
                            db: db
                        )
                    }
                    return item
                }
                return ClipboardItem(
                    id: id,
                    content: "Protected item".localized,
                    kind: kind,
                    createdAt: Date(timeIntervalSince1970: row["created_at"]),
                    isPinned: (row["is_pinned"] as Int) != 0,
                    pinnedOrder: row["pinned_order"],
                    containsSensitiveData: true,
                    userTitle: row["user_title"],
                    userNote: row["user_note"],
                    tags: tags,
                    protectionState: .locked
                )
            }
            let filePaths = try String.fetchAll(
                db,
                sql: """
                    SELECT path FROM file_paths
                    WHERE item_id = ?
                    ORDER BY ordinal
                    """,
                arguments: [id.uuidString]
            )
            let richText = try Row.fetchOne(
                db,
                sql: """
                    SELECT rtf_base64, html FROM rich_text
                    WHERE item_id = ?
                    """,
                arguments: [id.uuidString]
            )
            let pasteboardRepresentations = try Row.fetchAll(
                db,
                sql: """
                    SELECT item_index, type_identifier, data
                    FROM pasteboard_representations
                    WHERE item_id = ?
                    ORDER BY item_index, ordinal
                    """,
                arguments: [id.uuidString]
            ).map { representationRow in
                ClipboardPasteboardRepresentation(
                    itemIndex: representationRow["item_index"],
                    typeIdentifier: representationRow["type_identifier"],
                    data: representationRow["data"]
                )
            }

            return ClipboardItem(
                id: id,
                content: row["content"],
                kind: kind,
                createdAt: Date(timeIntervalSince1970: row["created_at"]),
                isPinned: (row["is_pinned"] as Int) != 0,
                pinnedOrder: row["pinned_order"],
                containsSensitiveData: (row["contains_sensitive_data"] as Int) != 0,
                sourceAppName: row["source_app_name"],
                sourceBundleIdentifier: row["source_bundle_identifier"],
                imageFileName: row["image_file_name"],
                imageWidth: row["image_width"],
                imageHeight: row["image_height"],
                imageByteCount: row["image_byte_count"],
                imageDigest: row["image_digest"],
                imagePerceptualHash: row["image_perceptual_hash"],
                imageSourceURL: row["image_source_url"],
                imageOriginalPath: row["image_original_path"],
                linkMetadata: Self.decodedJSON(from: row["link_metadata_json"]),
                detectedBarcodes: Self.decodedJSON(
                    from: row["detected_barcodes_json"]
                ),
                filePaths: filePaths.isEmpty ? nil : filePaths,
                richTextRTFBase64: richText?["rtf_base64"],
                richTextHTML: richText?["html"],
                pasteboardRepresentations: pasteboardRepresentations.isEmpty
                    ? nil
                    : pasteboardRepresentations,
                contentFileName: row["content_file_name"],
                contentDigest: row["content_digest"],
                contentCharacterCount: row["content_character_count"],
                contentLineCount: row["content_line_count"],
                contentByteCount: row["content_byte_count"],
                ocrText: row["ocr_text"],
                userTitle: row["user_title"],
                userNote: row["user_note"],
                tags: tags
            )
        }
    }

    func save(_ items: [ClipboardItem], db: Database) throws {
        let storedItems = try items.map { item in
            let protectedPayload: Data?
            let protectedPayloadDigest: String?
            if item.protectionState == .unlocked {
                let encodedItem = try Self.encodedProtectedPayload(item)
                protectedPayload = try protectedHistoryVault.encrypt(encodedItem)
                protectedPayloadDigest = ContentDigest.sha256Hex(for: encodedItem)
            } else {
                protectedPayload = nil
                protectedPayloadDigest = nil
            }
            return StoredItem(
                item: item,
                filePaths: item.isProtected ? [] : item.filePaths ?? [],
                richTextRTFBase64: item.isProtected ? nil : item.richTextRTFBase64,
                richTextHTML: item.isProtected ? nil : item.richTextHTML,
                pasteboardRepresentations: item.isProtected
                    ? []
                    : item.pasteboardRepresentations ?? [],
                protectedPayload: protectedPayload,
                protectedPayloadDigest: protectedPayloadDigest
            )
        }
        let existingFingerprints = try Dictionary(
            uniqueKeysWithValues: Row.fetchAll(
                db,
                sql: "SELECT id, fingerprint FROM items"
            ).map { row in
                (row["id"] as String, row["fingerprint"] as String)
            }
        )
        let indexedIDs = try searchIndexItemIDs(db: db)
        let snapshotIDs = Set(storedItems.map { $0.item.id.uuidString })
        try deleteStaleItems(
            retaining: snapshotIDs,
            existingIDs: Set(existingFingerprints.keys),
            db: db
        )

        for storedItem in storedItems {
            let item = storedItem.item
            let itemID = item.id.uuidString
            if item.protectionState == .locked {
                let existingMetadataVersion = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT protected_metadata_version FROM items WHERE id = ?
                        """,
                    arguments: [itemID]
                ) ?? 0
                let metadataVersion = existingMetadataVersion > 0 || item.hasUserMetadata
                    ? 1
                    : 0
                try db.execute(
                    sql: """
                        UPDATE items SET
                            is_pinned = ?, pinned_order = ?, created_at = ?, user_title = ?,
                            user_note = ?, protected_metadata_version = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        item.isPinned ? 1 : 0,
                        item.pinnedOrder,
                        item.createdAt.timeIntervalSince1970,
                        item.userTitle,
                        item.userNote,
                        metadataVersion,
                        itemID,
                    ]
                )
                try replaceTags(for: item, db: db)
                try refreshSearchIndex(for: storedItem, db: db)
                continue
            }
            let fingerprint = Self.fingerprint(for: storedItem)
            let needsItemRefresh = existingFingerprints[itemID] != fingerprint
            let needsSearchRefresh = indexedIDs.map { !$0.contains(itemID) } ?? false
            guard needsItemRefresh || needsSearchRefresh else {
                continue
            }
            if needsItemRefresh {
                try upsert(storedItem, fingerprint: fingerprint, db: db)
                try refreshChildren(for: storedItem, db: db)
            }
            try refreshSearchIndex(for: storedItem, db: db)
        }
    }

    func deleteStaleItems(
        retaining snapshotIDs: Set<String>,
        existingIDs: Set<String>,
        db: Database
    ) throws {
        let staleIDs = existingIDs.subtracting(snapshotIDs)
        guard !staleIDs.isEmpty else { return }
        let placeholders = Self.placeholders(count: staleIDs.count)
        let arguments = StatementArguments(Array(staleIDs))
        if try hasSearchIndex(db: db) {
            try db.execute(
                sql: "DELETE FROM search_index WHERE item_id IN (\(placeholders))",
                arguments: arguments
            )
        }
        try db.execute(
            sql: "DELETE FROM items WHERE id IN (\(placeholders))",
            arguments: arguments
        )
    }

    func upsert(
        _ storedItem: StoredItem,
        fingerprint: String,
        db: Database
    ) throws {
        let item = storedItem.item
        let protected = item.isProtected
        try db.execute(
            sql: """
                INSERT INTO items (
                    id, fingerprint, content, kind, created_at, is_pinned, pinned_order,
                    contains_sensitive_data, source_app_name,
                    source_bundle_identifier, image_file_name, image_width,
                    image_height, image_byte_count, image_digest,
                    image_perceptual_hash,
                    image_source_url, image_original_path, link_metadata_json,
                    detected_barcodes_json, content_file_name,
                    content_digest, content_character_count,
                    content_line_count, content_byte_count, ocr_text,
                    user_title, user_note,
                    is_protected, protected_payload, protected_metadata_version
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    fingerprint = excluded.fingerprint,
                    content = excluded.content,
                    kind = excluded.kind,
                    created_at = excluded.created_at,
                    is_pinned = excluded.is_pinned,
                    pinned_order = excluded.pinned_order,
                    contains_sensitive_data = excluded.contains_sensitive_data,
                    source_app_name = excluded.source_app_name,
                    source_bundle_identifier = excluded.source_bundle_identifier,
                    image_file_name = excluded.image_file_name,
                    image_width = excluded.image_width,
                    image_height = excluded.image_height,
                    image_byte_count = excluded.image_byte_count,
                    image_digest = excluded.image_digest,
                    image_perceptual_hash = excluded.image_perceptual_hash,
                    image_source_url = excluded.image_source_url,
                    image_original_path = excluded.image_original_path,
                    link_metadata_json = excluded.link_metadata_json,
                    detected_barcodes_json = excluded.detected_barcodes_json,
                    content_file_name = excluded.content_file_name,
                    content_digest = excluded.content_digest,
                    content_character_count = excluded.content_character_count,
                    content_line_count = excluded.content_line_count,
                    content_byte_count = excluded.content_byte_count,
                    ocr_text = excluded.ocr_text,
                    user_title = excluded.user_title,
                    user_note = excluded.user_note,
                    is_protected = excluded.is_protected,
                    protected_payload = excluded.protected_payload,
                    protected_metadata_version = excluded.protected_metadata_version
                """,
            arguments: [
                item.id.uuidString,
                fingerprint,
                protected ? "" : item.content,
                item.kind.rawValue,
                item.createdAt.timeIntervalSince1970,
                item.isPinned ? 1 : 0,
                item.pinnedOrder,
                protected ? 1 : (item.containsSensitiveData ? 1 : 0),
                protected ? nil : item.sourceAppName,
                protected ? nil : item.sourceBundleIdentifier,
                protected ? nil : item.imageFileName,
                protected ? nil : item.imageWidth,
                protected ? nil : item.imageHeight,
                protected ? nil : item.imageByteCount,
                protected ? nil : item.imageDigest,
                protected ? nil : item.imagePerceptualHash,
                protected ? nil : item.imageSourceURL,
                protected ? nil : item.imageOriginalPath,
                protected ? nil : Self.encodedJSON(item.linkMetadata),
                protected ? nil : Self.encodedJSON(item.detectedBarcodes),
                protected ? nil : item.contentFileName,
                protected ? nil : item.contentDigest,
                protected ? nil : item.contentCharacterCount,
                protected ? nil : item.contentLineCount,
                protected ? nil : item.contentByteCount,
                protected ? nil : item.ocrText,
                item.userTitle,
                item.userNote,
                protected ? 1 : 0,
                storedItem.protectedPayload,
                protected ? 1 : 0
            ]
        )
    }

    func refreshChildren(
        for storedItem: StoredItem,
        db: Database
    ) throws {
        let id = storedItem.item.id.uuidString
        try db.execute(
            sql: "DELETE FROM rich_text WHERE item_id = ?",
            arguments: [id]
        )
        if storedItem.richTextRTFBase64 != nil || storedItem.richTextHTML != nil {
            try db.execute(
                sql: """
                    INSERT INTO rich_text (item_id, rtf_base64, html)
                    VALUES (?, ?, ?)
                    """,
                arguments: [
                    id,
                    storedItem.richTextRTFBase64,
                    storedItem.richTextHTML
                ]
            )
        }

        try db.execute(
            sql: "DELETE FROM file_paths WHERE item_id = ?",
            arguments: [id]
        )
        for (index, path) in storedItem.filePaths.enumerated() {
            try db.execute(
                sql: """
                    INSERT INTO file_paths (item_id, ordinal, path)
                    VALUES (?, ?, ?)
                    """,
                arguments: [id, index, path]
            )
        }

        try db.execute(
            sql: "DELETE FROM pasteboard_representations WHERE item_id = ?",
            arguments: [id]
        )
        for (index, representation) in storedItem.pasteboardRepresentations.enumerated() {
            try db.execute(
                sql: """
                    INSERT INTO pasteboard_representations (
                        item_id, item_index, ordinal, type_identifier, data
                    )
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    id,
                    representation.itemIndex,
                    index,
                    representation.typeIdentifier,
                    representation.data
                ]
            )
        }

        try replaceTags(for: storedItem.item, db: db)
    }

    func tags(for id: UUID, db: Database) throws -> [String] {
        try String.fetchAll(
            db,
            sql: """
                SELECT normalized_name FROM item_tags
                WHERE item_id = ?
                ORDER BY ordinal
                """,
            arguments: [id.uuidString]
        )
    }


    func replaceTags(for item: ClipboardItem, db: Database) throws {
        let id = item.id.uuidString
        try db.execute(sql: "DELETE FROM item_tags WHERE item_id = ?", arguments: [id])
        for (index, tag) in (item.tags ?? []).enumerated() {
            try db.execute(
                sql: """
                    INSERT INTO item_tags (item_id, ordinal, normalized_name)
                    VALUES (?, ?, ?)
                    """,
                arguments: [id, index, tag]
            )
        }
    }


    static func fingerprint(for storedItem: StoredItem) -> String {
        let item = storedItem.item
        if item.isProtected {
            return ContentDigest.sha256Hex(
                for: [
                    item.id.uuidString,
                    item.kind.rawValue,
                    item.isPinned ? "1" : "0",
                    item.pinnedOrder.map(String.init) ?? "",
                    storedItem.protectedPayloadDigest ?? "locked",
                ].joined(separator: "\u{1E}")
            )
        }
        var parts: [String] = []
        parts.reserveCapacity(24 + storedItem.pasteboardRepresentations.count * 3)
        parts.append(item.id.uuidString)
        parts.append(item.content)
        parts.append(item.kind.rawValue)
        parts.append(String(item.createdAt.timeIntervalSince1970))
        parts.append(item.isPinned ? "1" : "0")
        parts.append(item.pinnedOrder.map(String.init) ?? "")
        parts.append(item.containsSensitiveData ? "1" : "0")
        parts.append(item.sourceAppName ?? "")
        parts.append(item.sourceBundleIdentifier ?? "")
        parts.append(item.imageFileName ?? "")
        parts.append(item.imageWidth.map(String.init) ?? "")
        parts.append(item.imageHeight.map(String.init) ?? "")
        parts.append(item.imageByteCount.map(String.init) ?? "")
        parts.append(item.imageDigest ?? "")
        parts.append(item.imagePerceptualHash ?? "")
        parts.append(item.imageSourceURL ?? "")
        parts.append(item.imageOriginalPath ?? "")
        parts.append(Self.encodedJSON(item.linkMetadata) ?? "")
        parts.append(Self.encodedJSON(item.detectedBarcodes) ?? "")
        parts.append(storedItem.filePaths.joined(separator: "\u{1F}"))
        parts.append(storedItem.richTextRTFBase64 ?? "")
        parts.append(storedItem.richTextHTML ?? "")
        for representation in storedItem.pasteboardRepresentations {
            parts.append(String(representation.itemIndex))
            parts.append(representation.typeIdentifier)
            parts.append(ContentDigest.sha256Hex(for: representation.data))
        }
        parts.append(item.contentFileName ?? "")
        parts.append(item.contentDigest ?? "")
        parts.append(item.contentCharacterCount.map(String.init) ?? "")
        parts.append(item.contentLineCount.map(String.init) ?? "")
        parts.append(item.contentByteCount.map(String.init) ?? "")
        parts.append(item.ocrText ?? "")
        parts.append(item.userTitle ?? "")
        parts.append(item.userNote ?? "")
        parts.append(item.tags?.joined(separator: "\u{1F}") ?? "")
        return ContentDigest.sha256Hex(for: parts.joined(separator: "\u{1E}"))
    }

    static func encodedProtectedPayload(_ item: ClipboardItem) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(item)
    }

    static func decodedJSON<Value: Decodable>(from json: String?) -> Value? {
        guard let json,
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    static func encodedJSON<Value: Encodable>(_ value: Value?) -> String? {
        guard let value,
              let data = try? JSONEncoder().encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
