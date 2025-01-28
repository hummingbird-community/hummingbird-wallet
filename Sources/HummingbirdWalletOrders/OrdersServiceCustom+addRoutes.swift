import FluentKit
import FluentWalletOrders
import Foundation
import Hummingbird
import HummingbirdFluent
import HummingbirdWallet

extension OrdersServiceCustom {
    typealias Context = BasicRequestContext

    /// Add the routes that Apple Wallet expects on your server to a `RouterGroup`.
    ///
    /// - Parameter group: The `RouterGroup` to add the routes to.
    public func addRoutes(to group: RouterGroup<BasicRequestContext>) {
        let orderTypeIdentifier = OrderDataType.typeIdentifier

        let v1 = group.group("v1")
        v1.get("devices/{deviceIdentifier}/registrations/\(orderTypeIdentifier)", use: self.ordersForDevice)
        v1.post("log", use: self.logMessage)

        let v1auth = v1.add(middleware: AppleOrderMiddleware<Context, OrderType>(fluent: self.fluent))
        v1auth.post("devices/{deviceIdentifier}/registrations/\(orderTypeIdentifier)/{orderIdentifier}", use: self.registerDevice)
        v1auth.get("orders/\(orderTypeIdentifier)/{orderIdentifier}", use: self.latestVersionOfOrder)
        v1auth.delete("devices/{deviceIdentifier}/registrations/\(orderTypeIdentifier)/{orderIdentifier}", use: self.unregisterDevice)
    }

    private func latestVersionOfOrder(_ req: Request, context: Context) async throws -> Response {
        self.logger.debug("Called latestVersionOfOrder")

        var ifModifiedSince: TimeInterval = 0
        if let header = req.headers[.ifModifiedSince], let ims = TimeInterval(header) {
            ifModifiedSince = ims
        }

        let id = try context.parameters.require("orderIdentifier", as: UUID.self)

        guard
            let order = try await OrderType.query(on: self.fluent.db())
                .filter(\._$id == id)
                .filter(\._$typeIdentifier == OrderDataType.typeIdentifier)
                .first()
        else {
            throw HTTPError(.notFound)
        }

        guard ifModifiedSince < order.updatedAt?.timeIntervalSince1970 ?? 0 else {
            throw HTTPError(.notModified)
        }

        guard
            let orderData = try await OrderDataType.query(on: self.fluent.db())
                .filter(\._$order.$id == id)
                .first()
        else {
            throw HTTPError(.notFound)
        }

        var headers = HTTPFields()
        headers[.contentType] = "application/vnd.apple.order"
        headers[.lastModified] = String((order.updatedAt ?? Date.distantPast).timeIntervalSince1970)
        headers[.contentEncoding] = "binary"
        return try await Response(
            status: .ok,
            headers: headers,
            body: .init(byteBuffer: .init(data: self.build(order: orderData)))
        )
    }

    private func registerDevice(_ req: Request, context: Context) async throws -> HTTPResponse.Status {
        self.logger.debug("Called register device")

        let pushToken = try await req.decode(as: PushTokenDTO.self, context: context).pushToken
        let orderIdentifier = try context.parameters.require("orderIdentifier", as: UUID.self)
        let deviceIdentifier = try context.parameters.require("deviceIdentifier")

        guard
            let order = try await OrderType.query(on: self.fluent.db())
                .filter(\._$id == orderIdentifier)
                .filter(\._$typeIdentifier == OrderDataType.typeIdentifier)
                .first()
        else {
            throw HTTPError(.notFound)
        }

        let device = try await DeviceType.query(on: self.fluent.db())
            .filter(\._$libraryIdentifier == deviceIdentifier)
            .filter(\._$pushToken == pushToken)
            .first()
        if let device = device {
            return try await self.createRegistration(device: device, order: order)
        } else {
            let newDevice = DeviceType(libraryIdentifier: deviceIdentifier, pushToken: pushToken)
            try await newDevice.create(on: self.fluent.db())
            return try await self.createRegistration(device: newDevice, order: order)
        }
    }

    private func createRegistration(device: DeviceType, order: OrderType) async throws -> HTTPResponse.Status {
        let r = try await OrdersRegistrationType.for(
            deviceLibraryIdentifier: device.libraryIdentifier,
            typeIdentifier: order.typeIdentifier,
            on: self.fluent.db()
        )
        .filter(OrderType.self, \._$id == order.requireID())
        .first()
        // If the registration already exists, docs say to return 200 OK
        if r != nil { return .ok }

        let registration = OrdersRegistrationType()
        registration._$order.id = try order.requireID()
        registration._$device.id = try device.requireID()
        try await registration.create(on: self.fluent.db())
        return .created
    }

    private func ordersForDevice(_ req: Request, context: Context) async throws -> OrderIdentifiersDTO {
        self.logger.debug("Called ordersForDevice")

        let deviceIdentifier = try context.parameters.require("deviceIdentifier")

        var query = OrdersRegistrationType.for(
            deviceLibraryIdentifier: deviceIdentifier,
            typeIdentifier: OrderDataType.typeIdentifier,
            on: self.fluent.db()
        )
        if let uriQuery = req.uri.queryParameters.get("ordersModifiedSince"),
            let since = TimeInterval(uriQuery)
        {
            let when = Date(timeIntervalSince1970: since)
            query = query.filter(OrderType.self, \._$updatedAt > when)
        }

        let registrations = try await query.all()
        guard !registrations.isEmpty else {
            throw HTTPError(.noContent)
        }

        var orderIdentifiers: [String] = []
        var maxDate = Date.distantPast
        for registration in registrations {
            let order = try await registration._$order.get(on: self.fluent.db())
            try orderIdentifiers.append(order.requireID().uuidString)
            if let updatedAt = order.updatedAt, updatedAt > maxDate {
                maxDate = updatedAt
            }
        }

        return OrderIdentifiersDTO(with: orderIdentifiers, maxDate: maxDate)
    }

    private func logMessage(_ req: Request, context: Context) async throws -> HTTPResponse.Status {
        let entries = try await req.decode(as: LogEntriesDTO.self, context: context)

        for log in entries.logs {
            self.logger.notice("HummingbirdWalletOrders: \(log)")
        }

        return .ok
    }

    private func unregisterDevice(_ req: Request, context: Context) async throws -> HTTPResponse.Status {
        self.logger.debug("Called unregisterDevice")

        let orderIdentifier = try context.parameters.require("orderIdentifier", as: UUID.self)
        let deviceIdentifier = try context.parameters.require("deviceIdentifier")

        guard
            let r = try await OrdersRegistrationType.for(
                deviceLibraryIdentifier: deviceIdentifier,
                typeIdentifier: OrderDataType.typeIdentifier,
                on: self.fluent.db()
            )
            .filter(OrderType.self, \._$id == orderIdentifier)
            .first()
        else {
            throw HTTPError(.notFound)
        }
        try await r.delete(on: self.fluent.db())
        return .ok
    }
}
