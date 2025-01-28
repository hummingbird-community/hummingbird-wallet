import APNS
import APNSCore
import FluentKit
import FluentWalletPasses
import Foundation
import Hummingbird
import HummingbirdFluent
import HummingbirdWallet
import NIOSSL
import ServiceLifecycle
import WalletPasses
import Zip

/// Struct to handle ``PassesService``.
///
/// The generics should be passed in this order:
/// - `PassDataModel`
/// - `PassModel`
/// - `PersonalizationInfoModel`
/// - `DeviceModel`
/// - `PassesRegistrationModel`
public struct PassesServiceCustom<
    PassDataType: PassDataModel,
    PassType: PassModel,
    PersonalizationInfoType: PersonalizationInfoModel,
    DeviceType: DeviceModel,
    PassesRegistrationType: PassesRegistrationModel
>: Sendable
where
    PassDataType.PassType == PassType,
    PersonalizationInfoType.PassType == PassType,
    PassesRegistrationType.PassType == PassType,
    PassesRegistrationType.DeviceType == DeviceType
{
    let logger: Logger
    let fluent: Fluent
    let builder: PassBuilder
    let apnsClient: APNSClient<JSONDecoder, JSONEncoder>

    /// Initializes the service and registers all the routes required for Apple Wallet to work.
    ///
    /// - Parameters:
    ///   - logger: The `Logger` instance to use.
    ///   - fluent: The `Fluent` instance to use.
    ///   - pemWWDRCertificate: Apple's WWDR.pem certificate in PEM format.
    ///   - pemCertificate: The PEM Certificate for signing passes.
    ///   - pemPrivateKey: The PEM Certificate's private key for signing passes.
    ///   - pemPrivateKeyPassword: The password to the private key. If the key is not encrypted it must be `nil`. Defaults to `nil`.
    ///   - openSSLPath: The location of the `openssl` command as a file path.
    public init(
        logger: Logger,
        fluent: Fluent,
        pemWWDRCertificate: String,
        pemCertificate: String,
        pemPrivateKey: String,
        pemPrivateKeyPassword: String? = nil,
        openSSLPath: String = "/usr/bin/openssl"
    ) throws {
        self.logger = logger
        self.fluent = fluent
        self.builder = PassBuilder(
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
            eventLoopGroupProvider: .createNew,
            responseDecoder: JSONDecoder(),
            requestEncoder: JSONEncoder()
        )
    }
}

extension PassesServiceCustom: Service {
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
extension PassesServiceCustom {
    /// Sends push notifications for a given pass.
    ///
    /// - Parameter passData: The pass to send the notifications for.
    public func sendPushNotifications(for passData: PassDataType) async throws {
        try await self.sendPushNotifications(for: passData._$pass.get(on: self.fluent.db()))
    }

    func sendPushNotifications(for pass: PassType) async throws {
        let registrations = try await self.registrations(for: pass)
        for reg in registrations {
            let backgroundNotification = APNSBackgroundNotification(
                expiration: .immediately,
                topic: reg.pass.typeIdentifier,
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

    private func registrations(for pass: PassType) async throws -> [PassesRegistrationType] {
        // This could be done by enforcing the caller to have a Siblings property wrapper,
        // but there's not really any value to forcing that on them when we can just do the query ourselves like this.
        try await PassesRegistrationType.query(on: self.fluent.db())
            .join(parent: \._$pass)
            .join(parent: \._$device)
            .with(\._$pass)
            .with(\._$device)
            .filter(PassType.self, \._$typeIdentifier == PassDataType.typeIdentifier)
            .filter(PassType.self, \._$id == pass.requireID())
            .all()
    }
}

// MARK: - Pass Building
extension PassesServiceCustom {
    /// Generates the pass content bundle for a given pass.
    ///
    /// - Parameter pass: The pass to generate the content for.
    ///
    /// - Returns: The generated pass content as `Data`.
    public func build(pass: PassDataType) async throws -> Data {
        try await self.builder.build(
            pass: pass.passJSON(on: self.fluent.db()),
            sourceFilesDirectoryPath: pass.sourceFilesDirectoryPath(on: self.fluent.db()),
            personalization: pass.personalizationJSON(on: self.fluent.db())
        )
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
        guard passes.count > 1 && passes.count <= 10 else {
            throw WalletPassesError.invalidNumberOfPasses
        }

        var files: [ArchiveFile] = []
        for (i, pass) in passes.enumerated() {
            try await files.append(ArchiveFile(filename: "pass\(i).pkpass", data: self.build(pass: pass)))
        }

        let zipFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pkpass")
        try Zip.zipData(archiveFiles: files, zipFilePath: zipFile)
        return try Data(contentsOf: zipFile)
    }
}
