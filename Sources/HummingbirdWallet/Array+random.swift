extension Array where Element: FixedWidthInteger {
    package static func random(count: Int) -> [Element] {
        var array: [Element] = .init(repeating: 0, count: count)
        for i in 0..<count {
            array[i] = Element.random(in: .min ... .max)
        }
        return array
    }
}
