import AsyncHTTPClient
import FluentWalletOrders
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

@testable import HummingbirdWalletOrders

@Suite("HummingbirdWalletOrders Tests")
struct HummingbirdWalletOrdersTests {
    let ordersURI = "/api/orders/v1/"

    @Test("Getting Order from Apple Wallet API", arguments: [true, false])
    func getOrderFromAPI(useEncryptedKey: Bool) async throws {
        let (app, fluent) = try await buildApplication(useEncryptedKey: useEncryptedKey)

        let orderData = OrderData(title: "Test Order")
        try await orderData.create(on: fluent.db())
        let order = try await orderData.$order.get(on: fluent.db())

        try await app.test(.router) { client in
            try await client.execute(
                uri: "\(ordersURI)orders/\(order.typeIdentifier)/\(order.requireID())",
                method: .get,
                headers: [
                    .authorization: "AppleOrder \(order.authenticationToken)",
                    .ifModifiedSince: "0",
                ]
            ) { response in
                #expect(response.status == .ok)
                #expect(response.body != nil)
                #expect(response.headers[.contentType] == "application/vnd.apple.order")
                #expect(response.headers[.lastModified] != nil)
            }

            // Test call with invalid authentication token
            try await client.execute(
                uri: "\(ordersURI)orders/\(order.typeIdentifier)/\(order.requireID())",
                method: .get,
                headers: [
                    .authorization: "AppleOrder invalid-token",
                    .ifModifiedSince: "0",
                ]
            ) { response in
                #expect(response.status == .unauthorized)
            }

            // Test distant future `If-Modified-Since` date
            try await client.execute(
                uri: "\(ordersURI)orders/\(order.typeIdentifier)/\(order.requireID())",
                method: .get,
                headers: [
                    .authorization: "AppleOrder \(order.authenticationToken)",
                    .ifModifiedSince: "2147483647",
                ]
            ) { response in
                #expect(response.status == .notModified)
            }

            // Test call with invalid order ID
            try await client.execute(
                uri: "\(ordersURI)orders/\(order.typeIdentifier)/invalid-uuid",
                method: .get,
                headers: [
                    .authorization: "AppleOrder \(order.authenticationToken)",
                    .ifModifiedSince: "0",
                ]
            ) { response in
                #expect(response.status == .unauthorized)
            }

            // Test call with invalid order type identifier
            try await client.execute(
                uri: "\(ordersURI)orders/order.com.example.InvalidType/\(order.requireID())",
                method: .get,
                headers: [
                    .authorization: "AppleOrder \(order.authenticationToken)",
                    .ifModifiedSince: "0",
                ]
            ) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test("Device Registration API")
    func apiDeviceRegistration() async throws {
        let (app, fluent) = try await buildApplication()

        let orderData = OrderData(title: "Test Order")
        try await orderData.create(on: fluent.db())
        let order = try await orderData.$order.get(on: fluent.db())
        let deviceLibraryIdentifier = "abcdefg"
        let pushTokenBytes = try JSONEncoder().encodeAsByteBuffer(PushTokenDTO(pushToken: "1234567890"), allocator: ByteBufferAllocator())

        try await app.test(.router) { client in
            try await client.execute(
                uri: "\(ordersURI)devices/\(deviceLibraryIdentifier)/registrations/\(order.typeIdentifier)?ordersModifiedSince=0",
                method: .get
            ) { response in
                #expect(response.status == .noContent)
            }

            try await client.execute(
                uri: "\(ordersURI)devices/\(deviceLibraryIdentifier)/registrations/\(order.typeIdentifier)/\(order.requireID())",
                method: .delete,
                headers: [.authorization: "AppleOrder \(order.authenticationToken)"]
            ) { response in
                #expect(response.status == .notFound)
            }

            // Test registration without authentication token
            try await client.execute(
                uri: "\(ordersURI)devices/\(deviceLibraryIdentifier)/registrations/\(order.typeIdentifier)/\(order.requireID())",
                method: .post,
                body: pushTokenBytes
            ) { response in
                #expect(response.status == .unauthorized)
            }

            // Test registration of a non-existing order
            try await client.execute(
                uri: "\(ordersURI)devices/\(deviceLibraryIdentifier)/registrations/\("order.com.example.NotFound")/\(UUID().uuidString)",
                method: .post,
                headers: [.authorization: "AppleOrder \(order.authenticationToken)"],
                body: pushTokenBytes
            ) { response in
                #expect(response.status == .notFound)
            }

            // Test call without DTO
            try await client.execute(
                uri: "\(ordersURI)devices/\(deviceLibraryIdentifier)/registrations/\(order.typeIdentifier)/\(order.requireID())",
                method: .post,
                headers: [.authorization: "AppleOrder \(order.authenticationToken)"]
            ) { response in
                #expect(response.status == .badRequest)
            }

            // Test call with invalid UUID
            try await client.execute(
                uri: "\(ordersURI)devices/\(deviceLibraryIdentifier)/registrations/\(order.typeIdentifier)/invalid-uuid",
                method: .post,
                headers: [.authorization: "AppleOrder \(order.authenticationToken)"],
                body: pushTokenBytes
            ) { response in
                #expect(response.status == .unauthorized)
            }

            try await client.execute(
                uri: "\(ordersURI)devices/\(deviceLibraryIdentifier)/registrations/\(order.typeIdentifier)/\(order.requireID())",
                method: .post,
                headers: [.authorization: "AppleOrder \(order.authenticationToken)"],
                body: pushTokenBytes
            ) { response in
                #expect(response.status == .created)
            }

            // Test registration of an already registered device
            try await client.execute(
                uri: "\(ordersURI)devices/\(deviceLibraryIdentifier)/registrations/\(order.typeIdentifier)/\(order.requireID())",
                method: .post,
                headers: [.authorization: "AppleOrder \(order.authenticationToken)"],
                body: pushTokenBytes
            ) { response in
                #expect(response.status == .ok)
            }

            try await client.execute(
                uri: "\(ordersURI)devices/\(deviceLibraryIdentifier)/registrations/\(order.typeIdentifier)?ordersModifiedSince=0",
                method: .get
            ) { response in
                let orders = try JSONDecoder().decode(OrderIdentifiersDTO.self, from: response.body)
                #expect(orders.orderIdentifiers.count == 1)
                let orderID = try order.requireID()
                #expect(orders.orderIdentifiers[0] == orderID.uuidString)
                #expect(orders.lastModified == String(order.updatedAt!.timeIntervalSince1970))
            }

            // Test call with invalid UUID
            try await client.execute(
                uri: "\(ordersURI)devices/\(deviceLibraryIdentifier)/registrations/\(order.typeIdentifier)/invalid-uuid",
                method: .delete,
                headers: [.authorization: "AppleOrder \(order.authenticationToken)"]
            ) { response in
                #expect(response.status == .unauthorized)
            }

            try await client.execute(
                uri: "\(ordersURI)devices/\(deviceLibraryIdentifier)/registrations/\(order.typeIdentifier)/\(order.requireID())",
                method: .delete,
                headers: [.authorization: "AppleOrder \(order.authenticationToken)"]
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
                uri: "\(ordersURI)log",
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

        let orderData = OrderData(title: "Test Order")
        try await orderData.create(on: fluent.db())

        // try await ordersService.sendPushNotifications(for: orderData, on: fluent.db())

        if !useEncryptedKey {
            // Test `AsyncModelMiddleware` update method
            orderData.title = "Test Order 2"
            do {
                try await orderData.update(on: fluent.db())
            } catch let error as HTTPClientError {
                #expect(error.self == .remoteConnectionClosed)
            }
        }
    }
}
