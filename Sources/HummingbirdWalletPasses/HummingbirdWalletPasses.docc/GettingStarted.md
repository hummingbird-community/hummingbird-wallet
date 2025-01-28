# Getting Started with Passes

Create the pass data model, build a pass for Apple Wallet and distribute it with a Hummingbird server.

## Overview

The `FluentWalletPasses` framework provides models to save all the basic information for passes, user devices and their registration to each pass.
For all the other custom data needed to generate the pass, such as the barcodes, locations, etc., you have to create your own model and its model middleware to handle the creation and update of passes.
The pass data model will be used to generate the `pass.json` file contents.

See [`FluentWalletPasses`'s documentation on `PassDataModel`](https://swiftpackageindex.com/fpseverino/fluent-wallet/documentation/fluentwalletpasses/passdatamodel) to understand how to implement the pass data model and do it before continuing with this guide.

The pass you distribute to a user is a signed bundle that contains the `pass.json` file, images and optional localizations.
The `HummingbirdWalletPasses` framework provides the ``PassesService`` class that handles the creation of the pass JSON file and the signing of the pass bundle.
The ``PassesService`` class also provides methods to send push notifications to all devices registered when you update a pass, and all the routes that Apple Wallet uses to retrieve passes.

### Initialize the Service

After creating the pass data model and the pass JSON data struct, initialize the ``PassesService`` inside the `buildApplication` method.

To implement all of the routes that Apple Wallet expects to exist on your server, don't forget to register them using the ``PassesService`` object as a route controller.

> Tip: Obtaining the three certificates files could be a bit tricky. You could get some guidance from [this guide](https://github.com/alexandercerutti/passkit-generator/wiki/Generating-Certificates) and [this video](https://www.youtube.com/watch?v=rJZdPoXHtzI).

```swift
import Hummingbird
import HummingbirdFluent
import HummingbirdWalletPasses

func buildApplication(_ arguments: some AppArguments) async throws -> some ApplicationProtocol {
    ...
    let passesService = try PassesService<PassData>(
        logger: logger,
        fluent: fluent,
        pemWWDRCertificate: env.get("PEM_WWDR_CERTIFICATE")!,
        pemCertificate: env.get("PEM_CERTIFICATE")!,
        pemPrivateKey: env.get("PEM_PRIVATE_KEY")!
    )

    try app.grouped("api", "passes").register(collection: passesService)

    ...

    let router = Router()
    passesService.addRoutes(to: router.group("/api/passes"))

    var app = Application(router: router)
    app.addServices(fluent, fluentPersist, passesService)
    return app
}
```

### Custom Implementation of PassesService

If you don't like the schema names provided by `FluentWalletPasses`, you can create your own models conforming to `PassModel`, `PersonalizationInfoModel`, `DeviceModel`, and `PassesRegistrationModel` and instantiate the generic ``PassesServiceCustom``, providing it your model types.

```swift
import Fluent
import FluentWalletPasses
import Hummingbird
import HummingbirdFluent
import HummingbirdWalletPasses

func buildApplication(_ arguments: some AppArguments) async throws -> some ApplicationProtocol {
    ...
    let passesService = try PassesServiceCustom<
        PassData,
        MyPassType,
        MyPersonalizationInfoType,
        MyDeviceType,
        MyPassesRegistrationType
    >(
        logger: logger,
        fluent: fluent,
        pemWWDRCertificate: env.get("PEM_WWDR_CERTIFICATE")!,
        pemCertificate: env.get("PEM_CERTIFICATE")!,
        pemPrivateKey: env.get("PEM_PRIVATE_KEY")!
    )

    try app.grouped("api", "passes").register(collection: passesService)

    ...

    let router = Router()
    passesService.addRoutes(to: router.group("/api/passes"))

    var app = Application(router: router)
    app.addServices(fluent, fluentPersist, passesService)
    return app
}
```

### Register Migrations

If you're using the default schemas provided by `FluentWalletPasses`, you have to add the migrations for the default models:

```swift
await passesService.addMigrations()
```

> Important: Register the default models before the migration of your pass data model.

### Pass Data Model Middleware

This framework provides a model middleware to handle the creation and update of the pass data model.

When you create a `PassDataModel` object, it will automatically create a `PassModel` object with a random auth token and the correct type identifier and link it to the pass data model.
When you update a pass data model, it will update the `PassModel` object and send a push notification to all devices registered to that pass.

You can register it like so (either with a ``PassesService`` or a ``PassesServiceCustom``):

```swift
fluent.databases.middleware.use(passesService, on: .psql)
```

> Note: If you don't like the default implementation of the model middleware, it is highly recommended that you create your own. But remember: whenever your pass data changes, you must update the `Pass.updatedAt` time of the linked `Pass` so that Wallet knows to retrieve a new pass.

### Generate the Pass Content

To generate and distribute the `.pkpass` bundle, pass the ``PassesService`` object to your route controller.

```swift
import Hummingbird
import HummingbirdFluent
import HummingbirdWalletPasses

struct PassesController {
    let fluent: Fluent
    let passesService: PassesService
    ...
}
```

Then use the object inside your route handlers to generate the pass bundle with the ``PassesService/build(pass:)`` method and distribute it with the "`application/vnd.apple.pkpass`" MIME type.

```swift
@Sendable func pass(_ req: Request, context: Context) async throws -> Response {
    ...
    guard let pass = try await PassData.query(on: fluent.db())
        .filter(...)
        .first()
    else {
        throw HTTPError(.notFound)
    }

    let bundle = try await passesService.build(pass: pass)
    var headers = HTTPFields()
    headers[.contentType] = "application/vnd.apple.pkpass"
    headers[.contentDisposition] = "attachment; filename=name.pkpass"
    headers[.lastModified] = String((pass.updatedAt ?? Date.distantPast).timeIntervalSince1970)
    headers[.contentEncoding] = "binary"
    return Response(
        status: .ok,
        headers: headers,
        body: .init(byteBuffer: .init(data: bundle))
    )
}
```

### Create a Bundle of Passes

You can also create a bundle of passes to enable your user to download multiple passes at once.
Use the ``PassesService/build(passes:)`` method to generate the bundle and serve it to the user.
The MIME type for a bundle of passes is "`application/vnd.apple.pkpasses`".

> Note: You can have up to 10 passes or 150 MB for a bundle of passes.

```swift
@Sendable func passes(_ req: Request, context: Context) async throws -> Response {
    ...
    let passes = try await PassData.query(on: fluent.db()).all()

    let bundle = try await passesService.build(passes: passes)
    var headers = HTTPFields()
    headers[.contentType] = "application/vnd.apple.pkpasses"
    headers[.contentDisposition] = "attachment; filename=name.pkpasses"
    headers[.lastModified] = String(Date().timeIntervalSince1970)
    headers[.contentEncoding] = "binary"
    return Response(
        status: .ok,
        headers: headers,
        body: .init(byteBuffer: .init(data: bundle))
    )
}
```

> Important: Bundles of passes are supported only in Safari. You can't send the bundle via AirDrop or other methods.
