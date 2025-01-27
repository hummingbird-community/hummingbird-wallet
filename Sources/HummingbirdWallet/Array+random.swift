extension Array where Element: FixedWidthInteger {
    package static func random(count: Int) -> [Element] {
        var array: [Element] = .init(repeating: 0, count: count)
        (0..<count).forEach { array[$0] = Element.random(in: .min ... .max) }
        return array
    }
}
