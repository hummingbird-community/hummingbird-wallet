# Hummingbird Wallet

🎟️ 📦 Create, distribute, and update passes and orders for the Apple Wallet app with Hummingbird.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fhummingbird-community%2Fhummingbird-wallet%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/hummingbird-community/hummingbird-wallet)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fhummingbird-community%2Fhummingbird-wallet%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/hummingbird-community/hummingbird-wallet)

[![](https://img.shields.io/github/actions/workflow/status/hummingbird-community/hummingbird-wallet/ci.yml?event=push&style=plastic&logo=github&label=tests&logoColor=%23ccc)](https://github.com/hummingbird-community/hummingbird-wallet/actions/workflows/ci.yml)
[![](https://img.shields.io/codecov/c/github/hummingbird-community/hummingbird-wallet?style=plastic&logo=codecov&label=codecov)](https://codecov.io/github/hummingbird-community/hummingbird-wallet)

Use the SPM string to easily include the dependendency in your `Package.swift` file.

```swift
.package(url: "https://github.com/hummingbird-community/hummingbird-wallet.git", from: "0.1.0")
```

## 🎟️ Wallet Passes

The `HummingbirdWalletPasses` framework provides a set of tools to help you create, build, and distribute digital passes for the Apple Wallet app using a Hummingbird server.
It also provides a way to update passes after they have been distributed, using APNs, and models to store pass and device data.

Add the `HummingbirdWalletPasses` product to your target's dependencies:

```swift
.product(name: "HummingbirdWalletPasses", package: "hummingbird-wallet")
```

See the framework's [documentation](https://swiftpackageindex.com/hummingbird-community/hummingbird-wallet/documentation/hummingbirdwalletpasses) for information and guides on how to use it.

For information on Apple Wallet passes, see the [Apple Developer Documentation](https://developer.apple.com/documentation/walletpasses).

## 📦 Wallet Orders

The `HummingbirdWalletOrders` framework provides a set of tools to help you create, build, and distribute orders that users can track and manage in Apple Wallet using a Hummingbird server.
It also provides a way to update orders after they have been distributed, using APNs, and models to store order and device data.

Add the `HummingbirdWalletOrders` product to your target's dependencies:

```swift
.product(name: "HummingbirdWalletOrders", package: "hummingbird-wallet")
```

See the framework's [documentation](https://swiftpackageindex.com/hummingbird-community/hummingbird-wallet/documentation/hummingbirdwalletorders) for information and guides on how to use it.

For information on Apple Wallet orders, see the [Apple Developer Documentation](https://developer.apple.com/documentation/walletorders).
