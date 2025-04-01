import AsyncHTTPClient
import FluentWalletPasses
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

@testable import HummingbirdWalletPasses

@Suite("HummingbirdWalletPasses Tests")
struct HummingbirdWalletPassesTests {
    let passesURI = "/api/passes/v1/"

    @Test("Getting Pass from Apple Wallet API", arguments: [true, false])
    func getPassFromAPI(useEncryptedKey: Bool) async throws {
        let (app, fluent) = try await buildApplication(useEncryptedKey: useEncryptedKey)

        let passData = PassData(title: "Test Pass")
        try await passData.create(on: fluent.db())
        let pass = try await passData.$pass.get(on: fluent.db())

        try await app.test(.router) { client in
            try await client.execute(
                uri: "\(passesURI)passes/\(pass.typeIdentifier)/\(pass.requireID())",
                method: .get,
                headers: [
                    .authorization: "ApplePass \(pass.authenticationToken)",
                    .ifModifiedSince: "0",
                ]
            ) { response in
                #expect(response.status == .ok)
                #expect(response.body.readableBytes > 0)
                #expect(response.headers[.contentType] == "application/vnd.apple.pkpass")
                #expect(response.headers[.lastModified] != nil)
            }

            // Test call with invalid authentication token
            try await client.execute(
                uri: "\(passesURI)passes/\(pass.typeIdentifier)/\(pass.requireID())",
                method: .get,
                headers: [
                    .authorization: "ApplePass invalid-token",
                    .ifModifiedSince: "0",
                ]
            ) { response in
                #expect(response.status == .unauthorized)
            }

            // Test distant future `If-Modified-Since` date
            try await client.execute(
                uri: "\(passesURI)passes/\(pass.typeIdentifier)/\(pass.requireID())",
                method: .get,
                headers: [
                    .authorization: "ApplePass \(pass.authenticationToken)",
                    .ifModifiedSince: "2147483647",
                ]
            ) { response in
                #expect(response.status == .notModified)
            }

            // Test call with invalid pass ID
            try await client.execute(
                uri: "\(passesURI)passes/\(pass.typeIdentifier)/invalid-uuid",
                method: .get,
                headers: [
                    .authorization: "ApplePass \(pass.authenticationToken)",
                    .ifModifiedSince: "0",
                ]
            ) { response in
                #expect(response.status == .unauthorized)
            }

            // Test call with invalid pass type identifier
            try await client.execute(
                uri: "\(passesURI)passes/pass.com.example.InvalidType/\(pass.requireID())",
                method: .get,
                headers: [
                    .authorization: "ApplePass \(pass.authenticationToken)",
                    .ifModifiedSince: "0",
                ]
            ) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test("Personalizable Pass Apple Wallet API", arguments: [true, false])
    func personalizationAPI(useEncryptedKey: Bool) async throws {
        let (app, fluent) = try await buildApplication(useEncryptedKey: useEncryptedKey)

        let passData = PassData(title: "Personalize")
        try await passData.create(on: fluent.db())
        let pass = try await passData.$pass.get(on: fluent.db())
        let personalizationDict = PersonalizationDictionaryDTO(
            personalizationToken: "1234567890",
            requiredPersonalizationInfo: .init(
                emailAddress: "test@example.com",
                familyName: "Doe",
                fullName: "John Doe",
                givenName: "John",
                isoCountryCode: "US",
                phoneNumber: "1234567890",
                postalCode: "12345"
            )
        )
        let personalizationDictBytes = try JSONEncoder().encodeAsByteBuffer(personalizationDict, allocator: ByteBufferAllocator())

        try await app.test(.router) { client in
            try await client.execute(
                uri: "\(passesURI)passes/\(pass.typeIdentifier)/\(pass.requireID())/personalize",
                method: .post,
                body: personalizationDictBytes
            ) { response in
                #expect(response.status == .ok)
                #expect(response.body.readableBytes > 0)
                #expect(response.headers[.contentType] == "application/octet-stream")
            }

            let personalizationQuery = try await PersonalizationInfo.query(on: fluent.db()).all()
            #expect(personalizationQuery.count == 1)
            #expect(personalizationQuery[0]._$emailAddress.value == personalizationDict.requiredPersonalizationInfo.emailAddress)
            #expect(personalizationQuery[0]._$familyName.value == personalizationDict.requiredPersonalizationInfo.familyName)
            #expect(personalizationQuery[0]._$fullName.value == personalizationDict.requiredPersonalizationInfo.fullName)
            #expect(personalizationQuery[0]._$givenName.value == personalizationDict.requiredPersonalizationInfo.givenName)
            #expect(personalizationQuery[0]._$isoCountryCode.value == personalizationDict.requiredPersonalizationInfo.isoCountryCode)
            #expect(personalizationQuery[0]._$phoneNumber.value == personalizationDict.requiredPersonalizationInfo.phoneNumber)
            #expect(personalizationQuery[0]._$postalCode.value == personalizationDict.requiredPersonalizationInfo.postalCode)

            // Test call with invalid pass ID
            try await client.execute(
                uri: "\(passesURI)passes/\(pass.typeIdentifier)/invalid-uuid/personalize",
                method: .post,
                body: personalizationDictBytes
            ) { response in
                #expect(response.status == .badRequest)
            }

            // Test call with invalid pass type identifier
            try await client.execute(
                uri: "\(passesURI)passes/pass.com.example.InvalidType/\(pass.requireID())/personalize",
                method: .post,
                body: personalizationDictBytes
            ) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test("Device Registration API")
    func apiDeviceRegistration() async throws {
        let (app, fluent) = try await buildApplication()

        let passData = PassData(title: "Test Pass")
        try await passData.create(on: fluent.db())
        let pass = try await passData.$pass.get(on: fluent.db())
        let deviceLibraryIdentifier = "abcdefg"
        let pushTokenBytes = try JSONEncoder().encodeAsByteBuffer(PushTokenDTO(pushToken: "1234567890"), allocator: ByteBufferAllocator())

        try await app.test(.router) { client in
            try await client.execute(
                uri: "\(passesURI)devices/\(deviceLibraryIdentifier)/registrations/\(pass.typeIdentifier)?passesUpdatedSince=0",
                method: .get
            ) { response in
                #expect(response.status == .noContent)
            }

            try await client.execute(
                uri: "\(passesURI)devices/\(deviceLibraryIdentifier)/registrations/\(pass.typeIdentifier)/\(pass.requireID())",
                method: .delete,
                headers: [.authorization: "ApplePass \(pass.authenticationToken)"]
            ) { response in
                #expect(response.status == .notFound)
            }

            // Test registration without authentication token
            try await client.execute(
                uri: "\(passesURI)devices/\(deviceLibraryIdentifier)/registrations/\(pass.typeIdentifier)/\(pass.requireID())",
                method: .post,
                body: pushTokenBytes
            ) { response in
                #expect(response.status == .unauthorized)
            }

            // Test registration of a non-existing pass
            try await client.execute(
                uri: "\(passesURI)devices/\(deviceLibraryIdentifier)/registrations/\("pass.com.example.NotFound")/\(UUID().uuidString)",
                method: .post,
                headers: [.authorization: "ApplePass \(pass.authenticationToken)"],
                body: pushTokenBytes
            ) { response in
                #expect(response.status == .notFound)
            }

            // Test call without DTO
            try await client.execute(
                uri: "\(passesURI)devices/\(deviceLibraryIdentifier)/registrations/\(pass.typeIdentifier)/\(pass.requireID())",
                method: .post,
                headers: [.authorization: "ApplePass \(pass.authenticationToken)"]
            ) { response in
                #expect(response.status == .badRequest)
            }

            // Test call with invalid UUID
            try await client.execute(
                uri: "\(passesURI)devices/\(deviceLibraryIdentifier)/registrations/\(pass.typeIdentifier)/invalid-uuid",
                method: .post,
                headers: [.authorization: "ApplePass \(pass.authenticationToken)"],
                body: pushTokenBytes
            ) { response in
                #expect(response.status == .unauthorized)
            }

            try await client.execute(
                uri: "\(passesURI)devices/\(deviceLibraryIdentifier)/registrations/\(pass.typeIdentifier)/\(pass.requireID())",
                method: .post,
                headers: [.authorization: "ApplePass \(pass.authenticationToken)"],
                body: pushTokenBytes
            ) { response in
                #expect(response.status == .created)
            }

            // Test registration of an already registered device
            try await client.execute(
                uri: "\(passesURI)devices/\(deviceLibraryIdentifier)/registrations/\(pass.typeIdentifier)/\(pass.requireID())",
                method: .post,
                headers: [.authorization: "ApplePass \(pass.authenticationToken)"],
                body: pushTokenBytes
            ) { response in
                #expect(response.status == .ok)
            }

            try await client.execute(
                uri: "\(passesURI)devices/\(deviceLibraryIdentifier)/registrations/\(pass.typeIdentifier)?passesUpdatedSince=0",
                method: .get
            ) { response in
                let passes = try JSONDecoder().decode(SerialNumbersDTO.self, from: response.body)
                #expect(passes.serialNumbers.count == 1)
                let passID = try pass.requireID()
                #expect(passes.serialNumbers[0] == passID.uuidString)
                #expect(passes.lastUpdated == String(pass.updatedAt!.timeIntervalSince1970))
            }

            // Test call with invalid UUID
            try await client.execute(
                uri: "\(passesURI)devices/\(deviceLibraryIdentifier)/registrations/\(pass.typeIdentifier)/invalid-uuid",
                method: .delete,
                headers: [.authorization: "ApplePass \(pass.authenticationToken)"]
            ) { response in
                #expect(response.status == .unauthorized)
            }

            try await client.execute(
                uri: "\(passesURI)devices/\(deviceLibraryIdentifier)/registrations/\(pass.typeIdentifier)/\(pass.requireID())",
                method: .delete,
                headers: [.authorization: "ApplePass \(pass.authenticationToken)"]
            ) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test("Log a Message")
    func errorLog() async throws {
        let (app, _) = try await buildApplication()

        let logEntries = LogEntriesDTO(logs: ["Error 1", "Error 2"])
        let logEntriesBytes = try JSONEncoder().encodeAsByteBuffer(logEntries, allocator: ByteBufferAllocator())

        try await app.test(.router) { client in
            try await client.execute(
                uri: "\(passesURI)log",
                method: .post,
                body: logEntriesBytes
            ) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test("APNS Client", arguments: [true, false])
    func apnsClient(useEncryptedKey: Bool) async throws {
        let (_, fluent) = try await buildApplication(useEncryptedKey: useEncryptedKey)

        let passData = PassData(title: "Test Pass")
        try await passData.create(on: fluent.db())

        // try await passesService.sendPushNotifications(for: passData, on: fluent.db())

        if !useEncryptedKey {
            // Test `AsyncModelMiddleware` update method
            passData.title = "Test Pass 2"
            do {
                try await passData.update(on: fluent.db())
            } catch let error as HTTPClientError {
                #expect(error.self == .remoteConnectionClosed)
            }
        }
    }
}
