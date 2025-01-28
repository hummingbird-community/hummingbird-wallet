# Getting Started with Orders

Create the order data model, build an order for Apple Wallet and distribute it with a Hummingbird server.

## Overview

The `FluentWalletOrders` framework provides models to save all the basic information for orders, user devices and their registration to each order.
For all the other custom data needed to generate the order, such as the barcodes, merchant info, etc., you have to create your own model and its model middleware to handle the creation and update of order.
The order data model will be used to generate the `order.json` file contents.

See [`FluentWalletOrders`'s documentation on `OrderDataModel`](https://swiftpackageindex.com/fpseverino/fluent-wallet/documentation/fluentwalletorders/orderdatamodel) to understand how to implement the order data model and do it before continuing with this guide.

The order you distribute to a user is a signed bundle that contains the `order.json` file, images, and optional localizations.
The `HummingbirdWalletOrders` framework provides the ``OrdersService`` class that handles the creation of the order JSON file and the signing of the order bundle.
The ``OrdersService`` class also provides methods to send push notifications to all devices registered when you update an order, and all the routes that Apple Wallet uses to retrieve orders.

### Initialize the Service

After creating the order data model and the order JSON data struct, initialize the ``OrdersService`` inside the `buildApplication` method.

To implement all of the routes that Apple Wallet expects to exist on your server, don't forget to register them using the ``OrdersService`` object as a route controller.

> Tip: Obtaining the three certificates files could be a bit tricky. You could get some guidance from [this guide](https://github.com/alexandercerutti/passkit-generator/wiki/Generating-Certificates) and [this video](https://www.youtube.com/watch?v=rJZdPoXHtzI). Those guides are for Wallet passes, but the process is similar for Wallet orders.

```swift
import Hummingbird
import HummingbirdFluent
import HummingbirdWalletOrders

func buildApplication(_ arguments: some AppArguments) async throws -> some ApplicationProtocol {
    ...
    let ordersService = try OrdersService<OrderData>(
        logger: logger,
        fluent: fluent,
        pemWWDRCertificate: env.get("PEM_WWDR_CERTIFICATE")!,
        pemCertificate: env.get("PEM_CERTIFICATE")!,
        pemPrivateKey: env.get("PEM_PRIVATE_KEY")!
    )

    ...

    let router = Router()
    ordersService.addRoutes(to: router.group("/api/orders"))

    var app = Application(router: router)
    app.addServices(fluent, fluentPersist, ordersService)
    return app
}
```

### Custom Implementation of OrdersService

If you don't like the schema names provided by `FluentWalletOrders`, you can create your own models conforming to `OrderModel`, `DeviceModel` and `OrdersRegistrationModel` and instantiate the generic ``OrdersServiceCustom``, providing it your model types.

```swift
import FluentWalletOrders
import Hummingbird
import HummingbirdFluent
import HummingbirdWalletOrders

func buildApplication(_ arguments: some AppArguments) async throws -> some ApplicationProtocol {
    ...
    let ordersService = try OrdersServiceCustom<
        OrderData,
        MyOrderType,
        MyDeviceType,
        MyOrdersRegistrationType
    >(
        logger: logger,
        fluent: fluent,
        pemWWDRCertificate: env.get("PEM_WWDR_CERTIFICATE")!,
        pemCertificate: env.get("PEM_CERTIFICATE")!,
        pemPrivateKey: env.get("PEM_PRIVATE_KEY")!
    )

    ...

    let router = Router()
    ordersService.addRoutes(to: router.group("/api/orders"))

    var app = Application(router: router)
    app.addServices(fluent, fluentPersist, ordersService)
    return app
}
```

### Register Migrations

If you're using the default schemas provided by `FluentWalletOrders`, you have to add the migrations for the default models:

```swift
await ordersService.addMigrations()
```

> Important: Register the default models before the migration of your order data model.

### Order Data Model Middleware

This framework provides a model middleware to handle the creation and update of the order data model.

When you create an `OrderDataModel` object, it will automatically create an `OrderModel` object with a random auth token and the correct type identifier and link it to the order data model.
When you update an order data model, it will update the `OrderModel` object and send a push notification to all devices registered to that order.

You can register it like so (either with an ``OrdersService`` or an ``OrdersServiceCustom``):

```swift
fluent.databases.middleware.use(ordersService, on: .psql)
```

> Note: If you don't like the default implementation of the model middleware, it is highly recommended that you create your own. But remember: whenever your order data changes, you must update the `Order.updatedAt` time of the linked `Order` so that Wallet knows to retrieve a new order.

### Generate the Order Content

To generate and distribute the `.order` bundle, pass the ``OrdersService`` object to your route controller.

```swift
import Hummingbird
import HummingbirdFluent
import HummingbirdWalletOrders

struct OrdersController {
    let fluent: Fluent
    let ordersService: OrdersService
    ...
}
```

Then use the object inside your route handlers to generate the order bundle with the ``OrdersService/build(order:)`` method and distribute it with the "`application/vnd.apple.order`" MIME type.

```swift
@Sendable func order(_ req: Request, context: Context) async throws -> Response {
    ...
    guard let order = try await OrderData.query(on: fluent.db())
        .filter(...)
        .first()
    else {
        throw HTTPError(.notFound)
    }

    let bundle = try await ordersService.build(order: order)
    var headers = HTTPFields()
    headers[.contentType] = "application/vnd.apple.order"
    headers[.contentDisposition] = "attachment; filename=name.order"
    headers[.lastModified] = String((order.updatedAt ?? Date.distantPast).timeIntervalSince1970)
    headers[.contentEncoding] = "binary"
    return Response(
        status: .ok,
        headers: headers,
        body: .init(byteBuffer: .init(data: bundle))
    )
}
```
