import FluentSQLiteDriver
import Foundation
import Hummingbird
import HummingbirdFluent
import HummingbirdWalletOrders

func buildApplication(useEncryptedKey: Bool = false) async throws -> (some ApplicationProtocol, Fluent) {
    let logger = Logger(label: "hummingbird-wallet-orders-tests")
    let fluent = Fluent(logger: logger)
    fluent.databases.use(.sqlite(.memory), as: .sqlite)

    let ordersService = try OrdersService<OrderData>(
        logger: logger,
        fluent: fluent,
        pemWWDRCertificate: TestCertificate.pemWWDRCertificate,
        pemCertificate: useEncryptedKey ? TestCertificate.encryptedPemCertificate : TestCertificate.pemCertificate,
        pemPrivateKey: useEncryptedKey ? TestCertificate.encryptedPemPrivateKey : TestCertificate.pemPrivateKey,
        pemPrivateKeyPassword: useEncryptedKey ? "password" : nil
    )

    await ordersService.addMigrations()
    await fluent.migrations.add(CreateOrderData())
    fluent.databases.middleware.use(ordersService, on: .sqlite)

    let fluentPersist = await FluentPersistDriver(fluent: fluent)
    try await fluent.migrate()

    let router = Router()
    ordersService.addRoutes(to: router.group("/api/orders"))

    var app = Application(router: router)
    app.addServices(fluent, fluentPersist, ordersService)
    return (app, fluent)
}
