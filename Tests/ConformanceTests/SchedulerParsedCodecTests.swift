import Foundation
import XCTest
import SurfaceDeviceContracts
import SurfaceFeedbackPlanning
import SurfaceDeviceConformance

final class SchedulerParsedCodecTests: XCTestCase {
    private func text(_ value: String) -> ScenarioPayload { .scalar(.text(value)) }
    // Test consumer boundary: strict raw gate and exact scalar decoding are
    // one shared call, with no intermediary NSNumber or independent visitor.
    private func parsed(_ raw: Data) throws -> ScenarioPayload {
        try SchedulerTraceCodec.decodePayload(raw)
    }
    private func assertExact(_ left: ScenarioPayload, _ right: ScenarioPayload, file: StaticString = #filePath, line: UInt = #line) {
        switch (left, right) {
        case let (.scalar(.number(a)), .scalar(.number(b))): XCTAssertEqual(a.bitPattern, b.bitPattern, file: file, line: line)
        case let (.scalar(.text(a)), .scalar(.text(b))): XCTAssertEqual(Array(a.utf8), Array(b.utf8), file: file, line: line)
        case let (.array(a), .array(b)):
            XCTAssertEqual(a.count, b.count, file: file, line: line)
            for (a, b) in zip(a, b) { assertExact(a, b, file: file, line: line) }
        case let (.object(a), .object(b)):
            XCTAssertEqual(Set(a.keys), Set(b.keys), file: file, line: line)
            for key in a.keys.sorted() { if let b = b[key] { assertExact(a[key]!, b, file: file, line: line) } }
        default: XCTAssertEqual(left, right, file: file, line: line)
        }
    }
    private func envelope(_ operation: String = "clear", arguments: String = "{}", context: String = "null") -> Data {
        Data(("{\"schema_version\":1,\"owner\":\"owned\",\"ordinal\":\"18446744073709551615\",\"operation\":\"" + operation + "\",\"arguments\":" + arguments + ",\"context\":" + context + "}").utf8)
    }
    private func operations() throws -> [SchedulerInput] {
        let opaque: ScenarioPayload = .object(["flag": .scalar(.flag(true)), "number": .scalar(.number(1)),
            "negative_zero": .scalar(.number(-0.0)), "null": .scalar(.null), "unknown": text("unknown"),
            "nfc": text("\u{e9}"), "nfd": text("e\u{301}"), "uint": text(String(UInt64.max))])
        let item = try SchedulerItem(key: "key", value: opaque, scope: .object(["attribution": .scalar(.null)]))
        let plan = try SchedulerTracePlan(reference: text("existing"), payload: item.value, origin: text("caller"), scope: item.scope,
            source: .hardware, endpointEvidence: EndpointProvenance(endpointID: nil, deviceID: nil, connectionGeneration: UInt64.max, transportOrigin: .unknown),
            capturedEvidence: opaque, targetID: "target", affectedElements: ["second", "first"], classification: .display, sideEffects: [.management], deliveryMode: .coalescible)
        let proof = SchedulerTraceProof(plan: plan, nativeSnapshot: opaque, authorization: .granted(directions: [.display, .management]), safety: .passed)
        let denied = SchedulerTraceProof(plan: plan, nativeSnapshot: .scalar(.null), authorization: .denied(reason: "actual-denial"), safety: .rejected(reason: "native-rejection"))
        return [.initialize(.unlimited), .initialize(.bucket(perSecond: 0.25, burst: 3, errorCooldown: 0)),
            .enqueue(item, ingress: .externalRequest), .enqueue(item, ingress: .derivedCallerRequeue(causeOrdinal: UInt64.max)),
            .cancel(key: "key"), .drain(at: -0.0), .failure(at: -978307200), .clear, .requestDirect(item),
            .changeStyle(style: item, projectionKey: "projection"), .invalidateCache(affectedKeys: ["second", "first", "first"]),
            .refreshDesired(order: ["second", "first"]), .release(key: "key"),
            .gate(SchedulerGateRecord(proposalOrdinal: UInt64.max, proposedItem: item, dispatchPlan: plan, proof: proof, currentScope: item.scope, currentNativeSnapshot: opaque)),
            .gate(SchedulerGateRecord(proposalOrdinal: 2, proposedItem: item, dispatchPlan: plan, proof: denied, currentScope: item.scope, currentNativeSnapshot: .scalar(.null))),
            .receipt(SchedulerActualReceipt(item: item, dispatchPlan: plan, result: .accepted, currentScope: item.scope)),
            .receipt(SchedulerActualReceipt(item: item, dispatchPlan: plan, result: .rejected(reason: "transport"), currentScope: .scalar(.null))),
            .receipt(SchedulerActualReceipt(item: item, dispatchPlan: plan, result: .notAttempted(reason: "preflight"), currentScope: opaque))]
    }

    func testEveryOperationUsesTheSameClosedParserAndCanonicalBytes() throws {
        var kinds: Set<String> = []
        for input in try operations() {
            let value = SchedulerEnvelope(owner: "owned", ordinal: UInt64.max, input: input)
            let raw = try SchedulerTraceCodec.encodeInput(value)
            let ast = try parsed(raw), fromData = try SchedulerTraceCodec.decodeInput(raw)
            let fromAST = try SchedulerTraceCodec.decodeInput(payload: ast)
            XCTAssertEqual(fromData, fromAST)
            XCTAssertEqual(try SchedulerTraceCodec.encodeInput(fromAST), raw)
            let reread = try parsed(SchedulerTraceCodec.encodeInput(fromAST))
            assertExact(ast, reread)
            if case .object(let object) = ast, case .scalar(.text(let name)) = object["operation"] { kinds.insert(name) }
        }
        XCTAssertEqual(kinds.count, 13)
    }

    func testParsedScalarBitsTypesAndUTF8MatchLegacyDataOracle() throws {
        let raw = envelope(context: #"{"true":true,"false":false,"one":1,"zero":0,"minus":-0,"minus_decimal":-0.0,"tiny":5e-324,"maximum":1.7976931348623157e308,"nfc":"é","nfd":"e\u0301","escaped":"\u00e9","surrogate":"\ud83d\ude00","nul":"\u0000","nothing":null,"unknown":"unknown","uint":"18446744073709551615"}"#)
        let oracle = try SchedulerTraceCodec.decodeInput(raw)
        let actual = try SchedulerTraceCodec.decodeInput(payload: parsed(raw))
        assertExact(oracle.context, actual.context)
        XCTAssertEqual(try SchedulerTraceCodec.encodeInput(actual), try SchedulerTraceCodec.encodeInput(oracle))
        guard case .object(let object) = actual.context,
              case .scalar(.number(let negative)) = object["minus"],
              case .scalar(.number(let tiny)) = object["tiny"],
              case .scalar(.text(let nfd)) = object["nfd"] else { return XCTFail("scalar representation") }
        XCTAssertEqual(negative.bitPattern, (-0.0).bitPattern)
        XCTAssertEqual(tiny.bitPattern, Double.leastNonzeroMagnitude.bitPattern)
        XCTAssertEqual(Array(nfd.utf8), [101, 204, 129])
        XCTAssertNotEqual(object["true"], object["one"])
        XCTAssertNotEqual(object["nothing"], object["unknown"])
    }

    func testASTRejectsNonfiniteValuesAnywhereWithoutMutation() throws {
        for bad in [Double.infinity, -.infinity, .nan] {
            var ast = try parsed(envelope())
            guard case .object(var object) = ast else { return XCTFail("envelope") }
            object["context"] = .array([.object(["nested": .scalar(.number(bad))])]); ast = .object(object)
            XCTAssertThrowsError(try SchedulerTraceCodec.decodeInput(payload: ast))
        }
    }

    func testASTAndDataRejectTheSameClosedSchemaErrors() throws {
        let invalid = [envelope("unknown"), envelope(arguments: #"{"native_pending":[]}"#),
            envelope("drain", arguments: #"{"at":true}"#), envelope("release", arguments: #"{"key":null}"#),
            Data(#"{"schema_version":true,"owner":"a","ordinal":"1","operation":"clear","arguments":{},"context":null}"#.utf8),
            Data(#"{"schema_version":1,"owner":"a","ordinal":1,"operation":"clear","arguments":{},"context":null}"#.utf8),
            Data(#"{"schema_version":1,"owner":"a","ordinal":"01","operation":"clear","arguments":{},"context":null}"#.utf8),
            Data(#"{"schema_version":1,"owner":"a","ordinal":"18446744073709551616","operation":"clear","arguments":{},"context":null}"#.utf8)]
        for raw in invalid {
            let ast = try parsed(raw)
            var dataError: SchedulerCandidateError?
            do { _ = try SchedulerTraceCodec.decodeInput(raw); XCTFail("Data accepted") }
            catch let error as SchedulerCandidateError { dataError = error }
            XCTAssertThrowsError(try SchedulerTraceCodec.decodeInput(payload: ast)) { error in
                XCTAssertEqual(error as? SchedulerCandidateError, dataError)
            }
        }
    }

    func testRawGateDoesNotGrantSchemaAdmissionAndASTDoesNotClaimRawProof() throws {
        try SchedulerTraceCodec.validateRawJSON(Data(#"{"arbitrary":[true,1,null]}"#.utf8))
        XCTAssertThrowsError(try SchedulerTraceCodec.decodeInput(payload: parsed(Data(#"{"arbitrary":[true,1,null]}"#.utf8))))
        // AST is a value API: it cannot represent duplicate source keys. The
        // raw gate on the original bytes is mandatory before conversion.
        let duplicate = Data(#"{"schema_version":1,"owner":"a","owner":"b","ordinal":"1","operation":"clear","arguments":{},"context":null}"#.utf8)
        XCTAssertThrowsError(try parsed(duplicate))
        XCTAssertThrowsError(try SchedulerTraceCodec.decodeInput(duplicate))
        let lostMultiplicity = try JSONDecoder().decode(ScenarioPayload.self, from: duplicate)
        XCTAssertNoThrow(try SchedulerTraceCodec.decodeInput(payload: lostMultiplicity))
    }

    func testStrictRawGrammarRejectsInvalidScalarsContainersAndEscapes() throws {
        let cases = ["", " ", "tru", "True", "false0", "NULL", "nil", "NaN", "Infinity", "-Infinity", "+1", ".1", "1.", "01", "-01", "--1", "-", "1e", "1e+", "1e-", "1e999", "-1e999", "1e-400", "2.4703282292062327e-324", "[1,]", "[,1]", "{\"a\":}", "{a:1}", "{\"a\":1,}", "{\"a\" 1}", "[true false]", "{}[]", "null x", "\"\\x\"", "\"\\uZZZZ\"", "\"\\u123\"", "\"\\ud800\"", "\"\\udc00\"", "\"\n\"", "\"unterminated"]
        for raw in cases { XCTAssertThrowsError(try SchedulerTraceCodec.validateRawJSON(Data(raw.utf8)), raw) }
        for raw in ["-0", "-0.0", "0e-3", "1.25E+3", "5e-324", "0e-4000", "-0e-4000", "true", "false", "null", " [ \"é\", \"\\ud83d\\ude00\" ] \r\n"] {
            XCTAssertNoThrow(try SchedulerTraceCodec.validateRawJSON(Data(raw.utf8)), raw)
        }
    }

    func testStrictRawUTF8ControlAndDecodedDuplicateKeys() throws {
        for bytes: [UInt8] in [[0x22, 0xff, 0x22], [0x22, 0xc0, 0xaf, 0x22], [0x22, 0xed, 0xa0, 0x80, 0x22], [0x22, 0, 0x22]] {
            XCTAssertThrowsError(try SchedulerTraceCodec.validateRawJSON(Data(bytes)))
        }
        let duplicate = [#"{"a":1,"a":2}"#, #"{"a":1,"\u0061":2}"#, #"{"nested":[{"a":1,"a":2}]}"#, #"{"é":1,"e\u0301":2}"#]
        for raw in duplicate { XCTAssertThrowsError(try SchedulerTraceCodec.validateRawJSON(Data(raw.utf8))) }
        XCTAssertNoThrow(try SchedulerTraceCodec.validateRawJSON(Data(#"[{"a":1},{"a":2}]"#.utf8)))
    }

    func testLegacyNumericTokenAcceptanceAndBitsArePreserved() throws {
        let accepted = ["-0", "-0.0", "0e-4000", "-0e-4000", "5e-324", "4.9406564584124654e-324", "-5e-324", "-0.004144001900805731"]
        for token in accepted {
            let raw = envelope(context: token)
            let legacy = try SchedulerTraceCodec.decodeInput(raw)
            try SchedulerTraceCodec.validateRawJSON(raw)
            let actual = try SchedulerTraceCodec.decodeInput(payload: parsed(raw))
            assertExact(legacy.context, actual.context)
            XCTAssertEqual(try SchedulerTraceCodec.encodeInput(legacy), try SchedulerTraceCodec.encodeInput(actual))
        }
        for token in ["1e-400", "2.4703282292062327e-324"] {
            let raw = envelope(context: token)
            XCTAssertThrowsError(try SchedulerTraceCodec.decodeInput(raw), token)
            XCTAssertThrowsError(try SchedulerTraceCodec.validateRawJSON(raw), token)
        }
    }

    func testOrdinaryDecimalULPRegressionRetainsLegacyBits() throws {
        let raw = envelope(context: "-0.004144001900805731")
        let legacy = try SchedulerTraceCodec.decodeInput(raw)
        let actual = try SchedulerTraceCodec.decodeInput(payload: parsed(raw))
        guard case .scalar(.number(let number)) = actual.context else { return XCTFail("number") }
        XCTAssertEqual(number.bitPattern, 0xbf70f94d0a376351)
        assertExact(legacy.context, actual.context)
        XCTAssertEqual(try SchedulerTraceCodec.encodeInput(legacy), try SchedulerTraceCodec.encodeInput(actual))
    }

    func testSeededFiniteDoublesPreserveEveryBitAndCanonicalByte() throws {
        var state: UInt64 = 0x105a9d84c73e26bf
        var checked = 0
        while checked < 1024 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let number = Double(bitPattern: state)
            guard number.isFinite else { continue }
            let value = SchedulerEnvelope(owner: "owned", ordinal: UInt64(checked + 1), input: .clear, context: .scalar(.number(number)))
            let raw = try SchedulerTraceCodec.encodeInput(value)
            let legacy = try SchedulerTraceCodec.decodeInput(raw)
            let actual = try SchedulerTraceCodec.decodeInput(payload: parsed(raw))
            assertExact(legacy.context, actual.context)
            XCTAssertEqual(try SchedulerTraceCodec.encodeInput(legacy), try SchedulerTraceCodec.encodeInput(actual))
            checked += 1
        }
        XCTAssertEqual(checked, 1024)
    }

    func testCanonicalEquivalentKeysFollowLegacyRawDuplicatePolicy() throws {
        let raw = envelope(context: #"{"é":1,"e\u0301":2}"#)
        for validate in [SchedulerTraceCodec.validateRawJSON, { _ = try SchedulerTraceCodec.decodeInput($0) }] {
            XCTAssertThrowsError(try validate(raw)) { error in
                XCTAssertEqual(error as? SchedulerCandidateError, .invalid("duplicate JSON key"))
            }
        }
        // A standalone Codable value probe is not the old guarded Data entry:
        // it has already lost the duplicate/canonically-equivalent key evidence.
        let unguarded = try JSONDecoder().decode(ScenarioPayload.self, from: raw)
        XCTAssertNoThrow(try SchedulerTraceCodec.decodeInput(payload: unguarded))
    }

    func testStrictRawDepthAndExactByteSizeBounds() throws {
        let limit = String(repeating: "[", count: 128) + "0" + String(repeating: "]", count: 128)
        try SchedulerTraceCodec.validateRawJSON(Data(limit.utf8))
        XCTAssertThrowsError(try SchedulerTraceCodec.validateRawJSON(Data(("[" + limit + "]").utf8)))
        let raw = Data(("\"" + String(repeating: "a", count: 1_048_574) + "\"").utf8)
        XCTAssertEqual(raw.count, 1_048_576)
        try SchedulerTraceCodec.validateRawJSON(raw)
        XCTAssertThrowsError(try SchedulerTraceCodec.validateRawJSON(raw + Data([32])))
    }

    func testOutputProtocolCannotBecomeInputThroughASTEntry() throws {
        var candidate = SchedulerCandidate()
        let step = try candidate.apply(SchedulerEnvelope(owner: "owned", ordinal: 1, input: .initialize(.unlimited)))
        let output = try SchedulerTraceCodec.encodeStep(step)
        XCTAssertThrowsError(try SchedulerTraceCodec.decodeInput(payload: parsed(output)))
        XCTAssertThrowsError(try SchedulerTraceCodec.decodeInput(output))
    }
}
