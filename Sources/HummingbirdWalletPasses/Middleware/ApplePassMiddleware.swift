import FluentKit
import FluentWalletPasses
import Foundation
import Hummingbird
import HummingbirdFluent

struct ApplePassMiddleware<Context: RequestContext, PassType: PassModel>: RouterMiddleware {
    let fluent: Fluent

    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        let id = try context.parameters.require("passSerial", as: UUID.self)
        guard
            let authToken = request.headers[.authorization]?.replacingOccurrences(of: "ApplePass ", with: ""),
            (try await PassType.query(on: self.fluent.db())
                .filter(\._$id == id)
                .filter(\._$authenticationToken == authToken)
                .first()) != nil
        else {
            throw HTTPError(.unauthorized)
        }
        return try await next(request, context)
    }
}
