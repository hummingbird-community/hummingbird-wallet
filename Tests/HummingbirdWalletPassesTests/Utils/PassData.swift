import FluentKit
import FluentWalletPasses
import Foundation
import WalletPasses

final class PassData: PassDataModel, @unchecked Sendable {
    static let schema = PassData.FieldKeys.schemaName

    static let typeIdentifier = "pass.com.hummingbird-community.HummingbirdWalletPasses"

    @ID(key: .id)
    var id: UUID?

    @Field(key: PassData.FieldKeys.title)
    var title: String

    @Parent(key: PassData.FieldKeys.passID)
    var pass: Pass

    init() {}

    init(id: UUID? = nil, title: String) {
        self.id = id
        self.title = title
    }
}

struct CreatePassData: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PassData.FieldKeys.schemaName)
            .id()
            .field(PassData.FieldKeys.title, .string, .required)
            .field(PassData.FieldKeys.passID, .uuid, .required, .references(Pass.schema, .id, onDelete: .cascade))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PassData.FieldKeys.schemaName).delete()
    }
}

extension PassData {
    enum FieldKeys {
        static let schemaName = "pass_data"
        static let title = FieldKey(stringLiteral: "title")
        static let passID = FieldKey(stringLiteral: "pass_id")
    }
}

extension PassData {
    func passJSON(on db: any Database) async throws -> any PassJSON.Properties {
        try await PassJSONData(data: self, pass: self.$pass.get(on: db))
    }

    func sourceFilesDirectoryPath(on db: any Database) async throws -> String {
        "\(FileManager.default.currentDirectoryPath)/Tests/HummingbirdWalletPassesTests/SourceFiles/"
    }

    func personalizationJSON(on db: any Database) async throws -> PersonalizationJSON? {
        if self.title != "Personalize" { return nil }

        let pass = try await self.$pass.get(on: db)

        let personalization = try await PersonalizationInfo.query(on: db)
            .filter(\.$pass.$id == pass.requireID())
            .first()

        if personalization == nil {
            return PersonalizationJSON(
                requiredPersonalizationFields: [.name, .postalCode, .emailAddress, .phoneNumber],
                description: "Hello, World!"
            )
        } else {
            return nil
        }
    }
}
