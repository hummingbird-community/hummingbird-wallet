import FluentKit
import FluentWalletPasses
import Foundation
import Hummingbird
import HummingbirdFluent
import ServiceLifecycle

/// The main struct that handles Apple Wallet passes.
public struct PassesService<PassDataType: PassDataModel>: Sendable where Pass == PassDataType.PassType {
    private let service: PassesServiceCustom<PassDataType, Pass, PersonalizationInfo, PassesDevice, PassesRegistration>

    /// Initializes the service and registers all the routes required for Apple Wallet to work.
    ///
    /// - Parameters:
    ///   - logger: The `Logger` instance to use.
    ///   - fluent: The `Fluent` instance to use.
    ///   - eventLoopGroup: The `EventLoopGroup` to run the service on.
    ///   - pemWWDRCertificate: Apple's WWDR.pem certificate in PEM format.
    ///   - pemCertificate: The PEM Certificate for signing passes.
    ///   - pemPrivateKey: The PEM Certificate's private key for signing passes.
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
        self.service = try PassesServiceCustom(
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

    /// Generates the pass content bundle for a given pass.
    ///
    /// - Parameter pass: The pass to generate the content for.
    ///
    /// - Returns: The generated pass content as `Data`.
    public func build(pass: PassDataType) async throws -> Data {
        try await service.build(pass: pass)
    }

    /// Generates a bundle of passes to enable your user to download multiple passes at once.
    ///
    /// > Note: You can have up to 10 passes or 150 MB for a bundle of passes.
    ///
    /// > Important: Bundles of passes are supported only in Safari. You can't send the bundle via AirDrop or other methods.
    ///
    /// - Parameter passes: The passes to include in the bundle.
    ///
    /// - Returns: The bundle of passes as `Data`.
    public func build(passes: [PassDataType]) async throws -> Data {
        try await service.build(passes: passes)
    }

    /// Adds the migrations for Apple Wallet passes models.
    ///
    /// - Parameter withPersonalization: Whether to include the migration for the `PersonalizationInfo` model. Defaults to `false`.
    public func addMigrations(withPersonalization: Bool = false) async {
        await self.service.fluent.migrations.add(CreatePass())
        await self.service.fluent.migrations.add(CreatePassesDevice())
        await self.service.fluent.migrations.add(CreatePassesRegistration())
        if withPersonalization {
            await self.service.fluent.migrations.add(CreatePersonalizationInfo())
        }
    }

    /// Sends push notifications for a given pass.
    ///
    /// - Parameter passData: The pass to send the notifications for.
    public func sendPushNotifications(for pass: PassDataType) async throws {
        try await self.service.sendPushNotifications(for: pass)
    }

    /// Add the routes that Apple Wallet expects on your server to a `RouterGroup`.
    ///
    /// - Parameter group: The `RouterGroup` to add the routes to.
    public func addRoutes(to group: RouterGroup<BasicRequestContext>) {
        self.service.addRoutes(to: group)
    }
}

extension PassesService: Service {
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
