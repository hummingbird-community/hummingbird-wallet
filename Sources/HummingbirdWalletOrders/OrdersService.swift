import FluentKit
import FluentWalletOrders
import Foundation
import Hummingbird
import HummingbirdFluent
import ServiceLifecycle

/// The main struct that handles Wallet orders.
public final class OrdersService<OrderDataType: OrderDataModel>: Sendable where Order == OrderDataType.OrderType {
    private let service: OrdersServiceCustom<OrderDataType, Order, OrdersDevice, OrdersRegistration>

    /// Initializes the service and registers all the routes required for Apple Wallet to work.
    ///
    /// - Parameters:
    ///   - logger: The `Logger` instance to use.
    ///   - fluent: The `Fluent` instance to use.
    ///   - eventLoopGroup: The `EventLoopGroup` to run the service on.
    ///   - pemWWDRCertificate: Apple's WWDR.pem certificate in PEM format.
    ///   - pemCertificate: The PEM Certificate for signing orders.
    ///   - pemPrivateKey: The PEM Certificate's private key for signing orders.
    ///   - pemPrivateKeyPassword: The password to the private key. If the key is not encrypted it must be `nil`. Defaults to `nil`.
    ///   - openSSLPath: The location of the `openssl` command as a file path.
    public init(
        logger: Logger,
        fluent: Fluent,
        eventLoopGroup: any EventLoopGroup,
        pemWWDRCertificate: String,
        pemCertificate: String,
        pemPrivateKey: String,
        pemPrivateKeyPassword: String? = nil,
        openSSLPath: String = "/usr/bin/openssl"
    ) throws {
        self.service = try OrdersServiceCustom(
            logger: logger,
            fluent: fluent,
            eventLoopGroup: eventLoopGroup,
            pemWWDRCertificate: pemWWDRCertificate,
            pemCertificate: pemCertificate,
            pemPrivateKey: pemPrivateKey,
            pemPrivateKeyPassword: pemPrivateKeyPassword,
            openSSLPath: openSSLPath
        )
    }

    /// Generates the order content bundle for a given order.
    ///
    /// - Parameter order: The order to generate the content for.
    ///
    /// - Returns: The generated order content as `Data`.
    public func build(order: OrderDataType) async throws -> Data {
        try await service.build(order: order)
    }

    /// Adds the migrations for Wallet orders models.
    public func register() async {
        await self.service.fluent.migrations.add(CreateOrder())
        await self.service.fluent.migrations.add(CreateOrdersDevice())
        await self.service.fluent.migrations.add(CreateOrdersRegistration())
    }

    /// Sends push notifications for a given order.
    ///
    /// - Parameter order: The order to send the notifications for.
    public func sendPushNotifications(for order: OrderDataType) async throws {
        try await service.sendPushNotifications(for: order)
    }
}

extension OrdersService: Service {
    /// Run the service.
    ///
    /// Waits for graceful shutdown and then shuts down the service.
    public func run() async throws {
        try? await gracefulShutdown()
        try await self.shutdown()
    }

    /// Shutdown the service.
    public func shutdown() async throws {
        try await self.service.shutdown()
    }
}
