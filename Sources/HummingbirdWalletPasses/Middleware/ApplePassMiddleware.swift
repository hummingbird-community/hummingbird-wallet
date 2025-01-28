import FluentKit
import FluentWalletPasses
import Foundation
import Hummingbird
import HummingbirdFluent

struct ApplePassMiddleware<Context: RequestContext, PassType: PassModel>: RouterMiddleware {
    let fluent: Fluent

    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        guard
            let id = context.parameters.get("passSerial", as: UUID.self),
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
