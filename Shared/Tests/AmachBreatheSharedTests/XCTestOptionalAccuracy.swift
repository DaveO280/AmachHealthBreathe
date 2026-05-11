import XCTest

func XCTAssertEqual(
    _ expression1: @autoclosure () throws -> Double?,
    _ expression2: @autoclosure () throws -> Double?,
    accuracy: Double,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        let lhs = try expression1()
        let rhs = try expression2()
        switch (lhs, rhs) {
        case let (left?, right?):
            XCTAssertEqual(left, right, accuracy: accuracy, message(), file: file, line: line)
        case (nil, nil):
            break
        default:
            XCTFail(message().isEmpty ? "Expected both values to be nil or non-nil" : message(), file: file, line: line)
        }
    } catch {
        XCTFail("Assertion threw error: \(error)", file: file, line: line)
    }
}

func XCTAssertEqual(
    _ expression1: @autoclosure () throws -> Double?,
    _ expression2: @autoclosure () throws -> Double,
    accuracy: Double,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        guard let lhs = try expression1() else {
            XCTFail(message().isEmpty ? "Expected non-nil Double" : message(), file: file, line: line)
            return
        }
        XCTAssertEqual(lhs, try expression2(), accuracy: accuracy, message(), file: file, line: line)
    } catch {
        XCTFail("Assertion threw error: \(error)", file: file, line: line)
    }
}
