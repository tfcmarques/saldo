import Foundation

enum AmountExpressionResult: Equatable {
    case value(Double)
    case incomplete
    case invalid
}

/// Evaluates the arithmetic typed into a money field.
///
/// A trailing `%` on the right side of `+` or `-` is that percent of the other side,
/// so `100 + 10%` is 110 and `80 - 10%` is 72. Anywhere else, `%` divides that number
/// by 100, so `200 * 15%` is 30.
enum AmountExpression {
    static func evaluate(_ raw: String, locale: Locale = .current) -> AmountExpressionResult {
        var source = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while source.hasSuffix("=") {
            source.removeLast()
            source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !source.isEmpty else { return .incomplete }
        guard source.count <= 200 else { return .invalid }

        var parser = Parser(source, locale: locale)
        do {
            let value = try parser.parse()
            return value.isFinite ? .value(value) : .invalid
        } catch Parser.Failure.incomplete {
            return .incomplete
        } catch {
            return .invalid
        }
    }

    /// True when the text is more than a single signed number, so the field should show a result.
    static func isCalculation(_ raw: String) -> Bool {
        let stripped = raw.filter { !$0.isWhitespace && !isCurrencySymbol($0) }
        guard let first = stripped.first else { return false }
        let body =
            isSign(first)
            ? stripped.dropFirst()
            : Substring(stripped)
        return body.contains(where: isOperatorMark)
    }

    static func rounded(_ value: Double, fractionDigits: Int) -> Double {
        guard value.isFinite else { return 0 }
        var input = Decimal(value)
        var output = Decimal()
        NSDecimalRound(&output, &input, fractionDigits, .plain)
        return NSDecimalNumber(decimal: output).doubleValue
    }

    static func formattedNumber(
        _ value: Double, fractionDigits: Int, locale: Locale = .current
    ) -> String {
        guard value.isFinite else { return "" }
        let normalized = value == 0 ? 0 : value
        return normalized.formatted(
            .number.precision(.fractionLength(fractionDigits)).locale(locale))
    }

    private static func isSign(_ character: Character) -> Bool {
        "+-−–—".contains(character)
    }

    private static func isOperatorMark(_ character: Character) -> Bool {
        "+-−–—*×/÷:%()=xX".contains(character)
    }

    fileprivate static func isCurrencySymbol(_ character: Character) -> Bool {
        "€$£¥₹₽₩₺¢฿₫₪₱₲₴₦₡₵".contains(character)
    }

    private struct Parser {
        enum Failure: Error {
            case incomplete
            case invalid
        }

        private let characters: [Character]
        private var index = 0
        private var depth = 0
        private let decimalSeparator: Character
        private let groupingSeparator: Character

        init(_ source: String, locale: Locale) {
            characters = Array(source)
            let decimal = locale.decimalSeparator?.first ?? "."
            let grouping = locale.groupingSeparator?.first
            decimalSeparator = decimal
            groupingSeparator = grouping == nil || grouping == decimal ? "\u{0}" : grouping!
        }

        mutating func parse() throws -> Double {
            let value = try parseExpression()
            skipIgnorable()
            guard index >= characters.count else { throw Failure.invalid }
            return value
        }

        private mutating func parseExpression() throws -> Double {
            try deepen()
            defer { depth -= 1 }

            var left = try parseTerm(consumeTrailingPercent: true)
            while true {
                skipIgnorable()
                if peek() == "%" {
                    index += 1
                    left /= 100
                    continue
                }
                guard let op = consumeAdditive() else { break }
                var right = try parseTerm(consumeTrailingPercent: false)
                skipIgnorable()
                if peek() == "%" {
                    index += 1
                    right = left * right / 100
                }
                left = op == "+" ? left + right : left - right
            }
            return left
        }

        private mutating func parseTerm(consumeTrailingPercent: Bool) throws -> Double {
            var left = try parseUnary()
            while true {
                skipIgnorable()
                if peek() == "%" {
                    let following = character(afterSkipping: "%")
                    if isMultiplicative(following) {
                        index += 1
                        left /= 100
                        continue
                    }
                    if consumeTrailingPercent {
                        index += 1
                        left /= 100
                        continue
                    }
                    break
                }
                guard let op = consumeMultiplicative() else { break }
                var right = try parseUnary()
                skipIgnorable()
                if peek() == "%", appliesToRightOperand(character(afterSkipping: "%")) {
                    index += 1
                    right /= 100
                }
                if op == "/" {
                    guard right != 0 else { throw Failure.invalid }
                    left /= right
                } else {
                    left *= right
                }
            }
            return left
        }

        private mutating func parseUnary() throws -> Double {
            try deepen()
            defer { depth -= 1 }
            skipIgnorable()
            if let sign = consumeAdditive() {
                let value = try parseUnary()
                return sign == "+" ? value : -value
            }
            return try parsePrimary()
        }

        private mutating func parsePrimary() throws -> Double {
            skipIgnorable()
            if consume("(") {
                let value = try parseExpression()
                skipIgnorable()
                if consume(")") { return value }
                throw index >= characters.count ? Failure.incomplete : Failure.invalid
            }
            if let number = try parseNumber() { return number }
            throw index >= characters.count ? Failure.incomplete : Failure.invalid
        }

        private mutating func parseNumber() throws -> Double? {
            skipIgnorable()
            let start = index
            var token = ""
            while index < characters.count {
                let character = characters[index]
                if isDigit(character) {
                    token.append(character)
                    index += 1
                } else if character == "." || character == "," {
                    token.append(character)
                    index += 1
                } else if character.isWhitespace, !token.isEmpty, nextSignificantIsDigit() {
                    skipWhitespaceRun()
                } else if isApostrophe(character), !token.isEmpty, nextIsDigit() {
                    index += 1
                } else {
                    break
                }
            }

            guard token.contains(where: isDigit) else {
                if token == "." || token == "," { throw Failure.incomplete }
                index = start
                return nil
            }

            if let last = token.last, last == "." || last == "," {
                let beforeSkip = index
                skipIgnorable()
                if index >= characters.count { throw Failure.incomplete }
                if isExpressionBoundary(peek()) {
                    token.removeLast()
                } else {
                    index = beforeSkip
                    throw Failure.invalid
                }
            }

            guard let value = interpret(token) else { throw Failure.invalid }
            return value
        }

        private func interpret(_ token: String) -> Double? {
            let chars = Array(token)
            let separatorIndexes = chars.indices.filter { chars[$0] == "." || chars[$0] == "," }
            let decimalIndex: Int?

            if separatorIndexes.isEmpty {
                decimalIndex = nil
            } else if Set(separatorIndexes.map { chars[$0] }).count == 2 {
                // 1,234.56 and 1.234,56 — the last separator is the decimal mark.
                decimalIndex = separatorIndexes.last
            } else if separatorIndexes.count > 1 {
                // 1,234,567 — repeated separators are thousands marks, not decimals.
                let separator = chars[separatorIndexes[0]]
                if separator == decimalSeparator && separator != groupingSeparator { return nil }
                decimalIndex = nil
            } else {
                // A single separator is the decimal mark, so 1,23 and 1.234 don't change
                // meaning when another digit is typed.
                decimalIndex = separatorIndexes[0]
            }

            var integer = ""
            var fraction = ""
            var groups: [Int] = []
            var groupLength = 0
            var inFraction = false

            for (offset, character) in chars.enumerated() {
                if let decimalIndex, offset == decimalIndex {
                    if groupLength > 0 || !groups.isEmpty { groups.append(groupLength) }
                    groupLength = 0
                    inFraction = true
                    continue
                }
                if character == "." || character == "," {
                    groups.append(groupLength)
                    groupLength = 0
                    continue
                }
                guard isDigit(character) else { return nil }
                if inFraction {
                    fraction.append(character)
                } else {
                    integer.append(character)
                    groupLength += 1
                }
            }
            if !inFraction { groups.append(groupLength) }

            if groups.count > 1 {
                guard let first = groups.first, (1...3).contains(first) else { return nil }
                guard groups.dropFirst().allSatisfy({ $0 == 3 }) else { return nil }
            }

            if integer.isEmpty {
                guard !fraction.isEmpty else { return nil }
                integer = "0"
            }

            let literal = inFraction ? "\(integer).\(fraction)" : integer
            return Double(literal)
        }

        private mutating func consumeAdditive() -> Character? {
            skipIgnorable()
            guard let character = peek(), isAdditive(character) else { return nil }
            index += 1
            return character == "+" ? "+" : "-"
        }

        private mutating func consumeMultiplicative() -> Character? {
            skipIgnorable()
            guard let character = peek() else { return nil }
            let normalized: Character
            switch character {
            case "*", "×", "x", "X": normalized = "*"
            case "/", "÷", ":": normalized = "/"
            default: return nil
            }
            index += 1
            return normalized
        }

        private mutating func consume(_ expected: Character) -> Bool {
            skipIgnorable()
            guard peek() == expected else { return false }
            index += 1
            return true
        }

        private func appliesToRightOperand(_ following: Character?) -> Bool {
            guard let following else { return true }
            if following == ")" || following == "%" || following == "=" { return true }
            return isAdditive(following) || isMultiplicative(following)
        }

        private func isAdditive(_ character: Character) -> Bool {
            "+-−–—".contains(character)
        }

        private func isMultiplicative(_ character: Character?) -> Bool {
            guard let character else { return false }
            return "*×xX/÷:".contains(character)
        }

        private func isExpressionBoundary(_ character: Character?) -> Bool {
            guard let character else { return true }
            return isAdditive(character) || isMultiplicative(character) || character == ")"
                || character == "%" || character == "=" || character == "("
        }

        private func isDigit(_ character: Character) -> Bool {
            character >= "0" && character <= "9"
        }

        private func isApostrophe(_ character: Character) -> Bool {
            character == "'" || character == "’" || character == "_"
        }

        private mutating func deepen() throws {
            guard depth < 96 else { throw Failure.invalid }
            depth += 1
        }

        private func peek() -> Character? {
            index < characters.count ? characters[index] : nil
        }

        private func character(afterSkipping token: Character) -> Character? {
            guard peek() == token else { return nil }
            var cursor = index + 1
            while cursor < characters.count, isIgnorable(characters[cursor]) { cursor += 1 }
            return cursor < characters.count ? characters[cursor] : nil
        }

        private func nextIsDigit() -> Bool {
            let next = index + 1
            return next < characters.count && isDigit(characters[next])
        }

        private func nextSignificantIsDigit() -> Bool {
            var cursor = index + 1
            while cursor < characters.count, characters[cursor].isWhitespace { cursor += 1 }
            return cursor < characters.count && isDigit(characters[cursor])
        }

        private mutating func skipWhitespaceRun() {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
        }

        private mutating func skipIgnorable() {
            while index < characters.count, isIgnorable(characters[index]) { index += 1 }
        }

        private func isIgnorable(_ character: Character) -> Bool {
            character.isWhitespace || AmountExpression.isCurrencySymbol(character)
        }
    }
}
