import FluentSQLiteDriver
import Foundation
import Hummingbird
import HummingbirdFluent
import HummingbirdWalletPasses

func buildApplication(useEncryptedKey: Bool = false) async throws -> (some ApplicationProtocol, Fluent) {
    let logger = Logger(label: "hummingbird-wallet-passes-tests")
    let fluent = Fluent(logger: logger)
    fluent.databases.use(.sqlite(.memory), as: .sqlite)

    let passesService = try PassesService<PassData>(
        logger: logger,
        fluent: fluent,
        pemWWDRCertificate: TestCertificate.pemWWDRCertificate,
        pemCertificate: useEncryptedKey ? TestCertificate.encryptedPemCertificate : TestCertificate.pemCertificate,
        pemPrivateKey: useEncryptedKey ? TestCertificate.encryptedPemPrivateKey : TestCertificate.pemPrivateKey,
        pemPrivateKeyPassword: useEncryptedKey ? "password" : nil
    )

    await passesService.addMigrations(withPersonalization: true)
    await fluent.migrations.add(CreatePassData())
    fluent.databases.middleware.use(passesService, on: .sqlite)

    let fluentPersist = await FluentPersistDriver(fluent: fluent)
    try await fluent.migrate()

    let router = Router()
    passesService.addRoutes(to: router.group("/api/passes"))

    var app = Application(router: router)
    app.addServices(fluent, fluentPersist, passesService)
    return (app, fluent)
}
