import Foundation

struct PasswordGeneratorOptions: Equatable, Sendable {
    static let defaultSymbols = "!@#$%&*"
    static let extendedSymbols = "!@#$%^&*()-_=+[]{};:,.?/"

    var length = 24
    var includesLowercase = true
    var includesUppercase = true
    var includesDigits = true
    var includesSymbols = true
    var allowedSymbols = PasswordGeneratorOptions.defaultSymbols
    var omitsAmbiguousCharacters = false
}

enum PasswordGeneratorError: Error, Equatable {
    case invalidLength
    case noCharacterClassesSelected
    case noSymbolsAvailable
    case lengthTooShortForSelectedClasses
}

enum PasswordGenerator {
    private static let lowercase = Array("abcdefghijklmnopqrstuvwxyz")
    private static let uppercase = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let digits = Array("0123456789")
    private static let ambiguous = Set("Il1O0o")

    static func generate(options: PasswordGeneratorOptions = PasswordGeneratorOptions()) throws -> String {
        guard (12...64).contains(options.length) else {
            throw PasswordGeneratorError.invalidLength
        }

        var pools: [[Character]] = []
        if options.includesLowercase { pools.append(filtered(lowercase, options: options)) }
        if options.includesUppercase { pools.append(filtered(uppercase, options: options)) }
        if options.includesDigits { pools.append(filtered(digits, options: options)) }
        if options.includesSymbols {
            let symbolPool = filtered(Array(normalizedSymbols(options.allowedSymbols)), options: options)
            guard !symbolPool.isEmpty else {
                throw PasswordGeneratorError.noSymbolsAvailable
            }
            pools.append(symbolPool)
        }

        guard !pools.isEmpty else {
            throw PasswordGeneratorError.noCharacterClassesSelected
        }
        guard options.length >= pools.count else {
            throw PasswordGeneratorError.lengthTooShortForSelectedClasses
        }

        var characters: [Character] = []
        for pool in pools {
            characters.append(try randomCharacter(from: pool))
        }

        let combined = pools.flatMap { $0 }
        while characters.count < options.length {
            characters.append(try randomCharacter(from: combined))
        }

        if characters.count > 1 {
            for index in stride(from: characters.count - 1, through: 1, by: -1) {
                let swapIndex = try SecureRandom.uniformIndex(upperBound: index + 1)
                characters.swapAt(index, swapIndex)
            }
        }
        return String(characters)
    }

    static func approximateEntropyBits(options: PasswordGeneratorOptions) -> Double {
        var poolCount = 0
        if options.includesLowercase { poolCount += filtered(lowercase, options: options).count }
        if options.includesUppercase { poolCount += filtered(uppercase, options: options).count }
        if options.includesDigits { poolCount += filtered(digits, options: options).count }
        if options.includesSymbols {
            poolCount += filtered(Array(normalizedSymbols(options.allowedSymbols)), options: options).count
        }
        guard poolCount > 1 else { return 0 }
        return Double(options.length) * log2(Double(poolCount))
    }

    private static func filtered(_ characters: [Character], options: PasswordGeneratorOptions) -> [Character] {
        guard options.omitsAmbiguousCharacters else { return characters }
        return characters.filter { !ambiguous.contains($0) }
    }

    static func normalizedSymbols(_ value: String) -> String {
        var seen = Set<Character>()
        return String(value.filter { character in
            !character.isWhitespace && seen.insert(character).inserted
        })
    }

    private static func randomCharacter(from pool: [Character]) throws -> Character {
        pool[try SecureRandom.uniformIndex(upperBound: pool.count)]
    }
}
