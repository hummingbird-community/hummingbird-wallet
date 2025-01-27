import APNS
import APNSCore
import FluentKit
import FluentWalletOrders
import Foundation
import Hummingbird
import HummingbirdFluent
import HummingbirdWallet
import NIO
import NIOSSL
import ServiceLifecycle
import WalletOrders

/// Struct to handle ``OrdersService``.
///
/// The generics should be passed in this order:
/// - `OrderDataModel`
/// - `OrderModel`
/// - `DeviceModel`
/// - `OrdersRegistrationModel`
public struct OrdersServiceCustom<
    OrderDataType: OrderDataModel,
    OrderType: OrderModel,
    DeviceType: DeviceModel,
    OrdersRegistrationType: OrdersRegistrationModel
>: Sendable
where
    OrderDataType.OrderType == OrderType,
    OrdersRegistrationType.OrderType == OrderType,
    OrdersRegistrationType.DeviceType == DeviceType
{
    let logger: Logger
    let fluent: Fluent
    let builder: OrderBuilder
    let apnsClient: APNSClient<JSONDecoder, JSONEncoder>

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
        self.logger = logger
        self.fluent = fluent
        self.builder = OrderBuilder(
            pemWWDRCertificate: pemWWDRCertificate,
            pemCertificate: pemCertificate,
            pemPrivateKey: pemPrivateKey,
            pemPrivateKeyPassword: pemPrivateKeyPassword,
            openSSLPath: openSSLPath
        )

        let privateKeyBytes = pemPrivateKey.data(using: .utf8)!.map { UInt8($0) }
        let certificateBytes = pemCertificate.data(using: .utf8)!.map { UInt8($0) }
        let apnsConfig: APNSClientConfiguration
        if let pemPrivateKeyPassword {
            apnsConfig = APNSClientConfiguration(
                authenticationMethod: try .tls(
                    privateKey: .privateKey(
                        NIOSSLPrivateKey(bytes: privateKeyBytes, format: .pem) { passphraseCallback in
                            passphraseCallback(pemPrivateKeyPassword.utf8)
                        }
                    ),
                    certificateChain: NIOSSLCertificate.fromPEMBytes(certificateBytes).map { .certificate($0) }
                ),
                environment: .production
            )
        } else {
            apnsConfig = APNSClientConfiguration(
                authenticationMethod: try .tls(
                    privateKey: .privateKey(NIOSSLPrivateKey(bytes: privateKeyBytes, format: .pem)),
                    certificateChain: NIOSSLCertificate.fromPEMBytes(certificateBytes).map { .certificate($0) }
                ),
                environment: .production
            )
        }

        self.apnsClient = APNSClient(
            configuration: apnsConfig,
            eventLoopGroupProvider: .shared(eventLoopGroup),
            responseDecoder: JSONDecoder(),
            requestEncoder: JSONEncoder()
        )
    }
}

extension OrdersServiceCustom: Service {
    /// Run the service.
    ///
    /// Waits for graceful shutdown and then shuts down the service.
    public func run() async throws {
        try? await gracefulShutdown()
        try await self.shutdown()
    }

    /// Shutdown the service.
    public func shutdown() async throws {
        try await self.apnsClient.shutdown()
    }
}

// MARK: - Push Notifications
extension OrdersServiceCustom {
    /// Sends push notifications for a given order.
    ///
    /// - Parameter orderData: The order to send the notifications for.
    public func sendPushNotifications(for orderData: OrderDataType) async throws {
        try await self.sendPushNotifications(for: orderData._$order.get(on: self.fluent.db()))
    }

    func sendPushNotifications(for order: OrderType) async throws {
        let registrations = try await self.registrations(for: order)
        for reg in registrations {
            let backgroundNotification = APNSBackgroundNotification(
                expiration: .immediately,
                topic: reg.order.typeIdentifier,
                payload: EmptyPayload()
            )
            do {
                try await self.apnsClient.sendBackgroundNotification(
                    backgroundNotification,
                    deviceToken: reg.device.pushToken
                )
            } catch let error as APNSCore.APNSError where error.reason == .badDeviceToken {
                try await reg.device.delete(on: self.fluent.db())
                try await reg.delete(on: self.fluent.db())
            }
        }
    }

    private func registrations(for order: OrderType) async throws -> [OrdersRegistrationType] {
        // This could be done by enforcing the caller to have a Siblings property wrapper,
        // but there's not really any value to forcing that on them when we can just do the query ourselves like this.
        try await OrdersRegistrationType.query(on: self.fluent.db())
            .join(parent: \._$order)
            .join(parent: \._$device)
            .with(\._$order)
            .with(\._$device)
            .filter(OrderType.self, \._$typeIdentifier == OrderDataType.typeIdentifier)
            .filter(OrderType.self, \._$id == order.requireID())
            .all()
    }
}

// MARK: - Order Building
extension OrdersServiceCustom {
    /// Generates the order content bundle for a given order.
    ///
    /// - Parameter order: The order to generate the content for.
    ///
    /// - Returns: The generated order content as `Data`.
    public func build(order: OrderDataType) async throws -> Data {
        try await self.builder.build(
            order: order.orderJSON(on: self.fluent.db()),
            sourceFilesDirectoryPath: order.sourceFilesDirectoryPath(on: self.fluent.db())
        )
    }
}
