import FluentKit
import FluentWalletOrders
import Foundation
import Hummingbird
import HummingbirdFluent

struct AppleOrderMiddleware<Context: RequestContext, OrderType: OrderModel>: RouterMiddleware {
    let fluent: Fluent

    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        let id = try context.parameters.require("orderIdentifier", as: UUID.self)
        guard
            let authToken = request.headers[.authorization]?.replacingOccurrences(of: "AppleOrder ", with: ""),
            (try await OrderType.query(on: self.fluent.db())
                .filter(\._$id == id)
                .filter(\._$authenticationToken == authToken)
                .first()) != nil
        else {
            throw HTTPError(.unauthorized)
        }
        return try await next(request, context)
    }
}
