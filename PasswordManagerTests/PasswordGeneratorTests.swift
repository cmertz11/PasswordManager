import XCTest
@testable import PasswordManager

final class PasswordGeneratorTests: XCTestCase {
    func testDefaultGeneratorMeetsConstraints() throws {
        for _ in 0..<100 {
            let password = try PasswordGenerator.generate()
            XCTAssertEqual(password.count, 24)
            XCTAssertTrue(password.contains(where: { $0.isLowercase }))
            XCTAssertTrue(password.contains(where: { $0.isUppercase }))
            XCTAssertTrue(password.contains(where: { $0.isNumber }))
            XCTAssertTrue(password.contains(where: { PasswordGeneratorOptions.defaultSymbols.contains($0) }))
        }
    }

    func testOmittingAmbiguousCharacters() throws {
        var options = PasswordGeneratorOptions()
        options.length = 64
        options.omitsAmbiguousCharacters = true

        for _ in 0..<50 {
            let password = try PasswordGenerator.generate(options: options)
            XCTAssertFalse(password.contains(where: { "Il1O0o".contains($0) }))
        }
    }

    func testRejectsNoSelectedClasses() {
        let options = PasswordGeneratorOptions(
            includesLowercase: false,
            includesUppercase: false,
            includesDigits: false,
            includesSymbols: false
        )
        XCTAssertThrowsError(try PasswordGenerator.generate(options: options)) { error in
            XCTAssertEqual(error as? PasswordGeneratorError, .noCharacterClassesSelected)
        }
    }

    func testRejectsLengthsOutsideSupportedRange() {
        var options = PasswordGeneratorOptions()
        options.length = 11
        XCTAssertThrowsError(try PasswordGenerator.generate(options: options)) { error in
            XCTAssertEqual(error as? PasswordGeneratorError, .invalidLength)
        }

        options.length = 65
        XCTAssertThrowsError(try PasswordGenerator.generate(options: options)) { error in
            XCTAssertEqual(error as? PasswordGeneratorError, .invalidLength)
        }
    }

    func testSingleSelectedClassContainsOnlyAllowedCharacters() throws {
        let options = PasswordGeneratorOptions(
            length: 64,
            includesLowercase: false,
            includesUppercase: false,
            includesDigits: true,
            includesSymbols: false
        )
        let password = try PasswordGenerator.generate(options: options)

        XCTAssertEqual(password.count, 64)
        XCTAssertTrue(password.allSatisfy(\.isNumber))
    }

    func testCustomSymbolOverrideUsesOnlyAllowedSymbols() throws {
        let options = PasswordGeneratorOptions(
            length: 64,
            includesLowercase: false,
            includesUppercase: false,
            includesDigits: false,
            includesSymbols: true,
            allowedSymbols: "-_"
        )

        let password = try PasswordGenerator.generate(options: options)

        XCTAssertEqual(password.count, 64)
        XCTAssertTrue(password.allSatisfy { "-_".contains($0) })
    }

    func testFidelityStyleSymbolOverrideUsesOnlyItsSiteDefinition() throws {
        let fidelitySymbols = "!@$%^()-_+=|\\:;',.?/~"
        let options = PasswordGeneratorOptions(
            length: 64,
            includesLowercase: false,
            includesUppercase: false,
            includesDigits: false,
            includesSymbols: true,
            allowedSymbols: fidelitySymbols
        )

        let password = try PasswordGenerator.generate(options: options)

        XCTAssertEqual(password.count, 64)
        XCTAssertTrue(password.allSatisfy { fidelitySymbols.contains($0) })
    }

    func testRejectsAnEmptyCustomSymbolSet() {
        let options = PasswordGeneratorOptions(
            includesLowercase: true,
            includesUppercase: true,
            includesDigits: true,
            includesSymbols: true,
            allowedSymbols: "   "
        )

        XCTAssertThrowsError(try PasswordGenerator.generate(options: options)) { error in
            XCTAssertEqual(error as? PasswordGeneratorError, .noSymbolsAvailable)
        }
    }
}
