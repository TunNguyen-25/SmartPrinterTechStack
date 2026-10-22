import Foundation

nonisolated struct LibraryDocument: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let name: String
}
