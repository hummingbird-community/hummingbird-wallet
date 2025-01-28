import FluentKit
import FluentWalletPasses
import Foundation
import Hummingbird
import HummingbirdFluent
import HummingbirdWallet

extension PassesServiceCustom {
    typealias Context = BasicRequestContext

    /// Add the routes that Apple Wallet expects on your server to a `RouterGroup`.
    ///
    /// - Parameter group: The `RouterGroup` to add the routes to.
    public func addRoutes(to group: RouterGroup<BasicRequestContext>) {
        let passTypeIdentifier = PassDataType.typeIdentifier

        let v1 = group.group("v1")
        v1.get("devices/{deviceLibraryIdentifier}/registrations/\(passTypeIdentifier)", use: self.updatablePasses)
        v1.post("log", use: self.logMessage)
        v1.post("passes/\(passTypeIdentifier)/{passSerial}/personalize", use: self.personalizedPass)

        let v1auth = v1.add(middleware: ApplePassMiddleware<Context, PassType>(fluent: self.fluent))
        v1auth.post("devices/{deviceLibraryIdentifier}/registrations/\(passTypeIdentifier)/{passSerial}", use: self.registerPass)
        v1auth.get("passes/\(passTypeIdentifier)/{passSerial}", use: self.updatedPass)
        v1auth.delete("devices/{deviceLibraryIdentifier}/registrations/\(passTypeIdentifier)/{passSerial}", use: self.unregisterPass)
    }

    private func registerPass(_ req: Request, context: Context) async throws -> HTTPResponse.Status {
        self.logger.debug("Called register pass")

        let pushToken = try await req.decode(as: PushTokenDTO.self, context: context).pushToken
        let serial = try context.parameters.require("passSerial", as: UUID.self)
        let deviceLibraryIdentifier = try context.parameters.require("deviceLibraryIdentifier")

        guard
            let pass = try await PassType.query(on: self.fluent.db())
                .filter(\._$typeIdentifier == PassDataType.typeIdentifier)
                .filter(\._$id == serial)
                .first()
        else {
            throw HTTPError(.notFound)
        }

        let device = try await DeviceType.query(on: self.fluent.db())
            .filter(\._$libraryIdentifier == deviceLibraryIdentifier)
            .filter(\._$pushToken == pushToken)
            .first()
        if let device {
            return try await self.createRegistration(device: device, pass: pass)
        } else {
            let newDevice = DeviceType(libraryIdentifier: deviceLibraryIdentifier, pushToken: pushToken)
            try await newDevice.create(on: self.fluent.db())
            return try await self.createRegistration(device: newDevice, pass: pass)
        }
    }

    private func createRegistration(device: DeviceType, pass: PassType) async throws -> HTTPResponse.Status {
        let r = try await PassesRegistrationType.for(
            deviceLibraryIdentifier: device.libraryIdentifier,
            typeIdentifier: pass.typeIdentifier,
            on: self.fluent.db()
        )
        .filter(PassType.self, \._$id == pass.requireID())
        .first()
        // If the registration already exists, docs say to return 200 OK
        if r != nil { return .ok }

        let registration = PassesRegistrationType()
        registration._$pass.id = try pass.requireID()
        registration._$device.id = try device.requireID()
        try await registration.create(on: self.fluent.db())
        return .created
    }

    private func updatablePasses(_ req: Request, context: Context) async throws -> SerialNumbersDTO {
        self.logger.debug("Called updatablePasses")

        let deviceLibraryIdentifier = try context.parameters.require("deviceLibraryIdentifier")

        var query = PassesRegistrationType.for(
            deviceLibraryIdentifier: deviceLibraryIdentifier,
            typeIdentifier: PassDataType.typeIdentifier,
            on: self.fluent.db()
        )
        if let uriQuery = req.uri.queryParameters.get("passesUpdatedSince"),
            let since = TimeInterval(uriQuery)
        {
            let when = Date(timeIntervalSince1970: since)
            query = query.filter(PassType.self, \._$updatedAt > when)
        }

        let registrations = try await query.all()
        guard !registrations.isEmpty else {
            throw HTTPError(.noContent)
        }

        var serialNumbers: [String] = []
        var maxDate = Date.distantPast
        for registration in registrations {
            let pass = try await registration._$pass.get(on: self.fluent.db())
            try serialNumbers.append(pass.requireID().uuidString)
            if let updatedAt = pass.updatedAt, updatedAt > maxDate {
                maxDate = updatedAt
            }
        }

        return SerialNumbersDTO(with: serialNumbers, maxDate: maxDate)
    }

    private func updatedPass(_ req: Request, context: Context) async throws -> Response {
        self.logger.debug("Called updatedPass")

        var ifModifiedSince: TimeInterval = 0
        if let header = req.headers[.ifModifiedSince], let ims = TimeInterval(header) {
            ifModifiedSince = ims
        }

        let id = try context.parameters.require("passSerial", as: UUID.self)

        guard
            let pass = try await PassType.query(on: self.fluent.db())
                .filter(\._$id == id)
                .filter(\._$typeIdentifier == PassDataType.typeIdentifier)
                .first()
        else {
            throw HTTPError(.notFound)
        }

        guard ifModifiedSince < pass.updatedAt?.timeIntervalSince1970 ?? 0 else {
            throw HTTPError(.notModified)
        }

        guard
            let passData = try await PassDataType.query(on: self.fluent.db())
                .filter(\._$pass.$id == id)
                .first()
        else {
            throw HTTPError(.notFound)
        }

        var headers = HTTPFields()
        headers[.contentType] = "application/vnd.apple.pkpass"
        headers[.lastModified] = String((pass.updatedAt ?? Date.distantPast).timeIntervalSince1970)
        headers[.contentEncoding] = "binary"
        return try await Response(
            status: .ok,
            headers: headers,
            body: .init(byteBuffer: .init(data: self.build(pass: passData)))
        )
    }

    private func unregisterPass(_ req: Request, context: Context) async throws -> HTTPResponse.Status {
        self.logger.debug("Called unregisterPass")

        let passId = try context.parameters.require("passSerial", as: UUID.self)
        let deviceLibraryIdentifier = try context.parameters.require("deviceLibraryIdentifier")

        guard
            let r = try await PassesRegistrationType.for(
                deviceLibraryIdentifier: deviceLibraryIdentifier,
                typeIdentifier: PassDataType.typeIdentifier,
                on: self.fluent.db()
            )
            .filter(PassType.self, \._$id == passId)
            .first()
        else {
            throw HTTPError(.notFound)
        }
        try await r.delete(on: self.fluent.db())
        return .ok
    }

    private func logMessage(_ req: Request, context: Context) async throws -> HTTPResponse.Status {
        let entries = try await req.decode(as: LogEntriesDTO.self, context: context)

        for log in entries.logs {
            self.logger.notice("HummingbirdWalletPasses: \(log)")
        }

        return .ok
    }

    private func personalizedPass(_ req: Request, context: Context) async throws -> Response {
        self.logger.debug("Called personalizedPass")

        let id = try context.parameters.require("passSerial", as: UUID.self)

        guard
            try await PassType.query(on: self.fluent.db())
                .filter(\._$id == id)
                .filter(\._$typeIdentifier == PassDataType.typeIdentifier)
                .first() != nil
        else {
            throw HTTPError(.notFound)
        }

        let userInfo = try await req.decode(as: PersonalizationDictionaryDTO.self, context: context)

        let personalization = PersonalizationInfoType()
        personalization.fullName = userInfo.requiredPersonalizationInfo.fullName
        personalization.givenName = userInfo.requiredPersonalizationInfo.givenName
        personalization.familyName = userInfo.requiredPersonalizationInfo.familyName
        personalization.emailAddress = userInfo.requiredPersonalizationInfo.emailAddress
        personalization.postalCode = userInfo.requiredPersonalizationInfo.postalCode
        personalization.isoCountryCode = userInfo.requiredPersonalizationInfo.isoCountryCode
        personalization.phoneNumber = userInfo.requiredPersonalizationInfo.phoneNumber
        personalization._$pass.id = id
        try await personalization.create(on: self.fluent.db())

        guard let token = userInfo.personalizationToken.data(using: .utf8) else {
            throw HTTPError(.internalServerError)
        }

        var headers = HTTPFields()
        headers[.contentType] = "application/octet-stream"
        headers[.contentEncoding] = "binary"
        return try Response(
            status: .ok,
            headers: headers,
            body: .init(byteBuffer: .init(data: self.builder.signature(for: token)))
        )
    }
}
