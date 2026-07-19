//
//  ChecklistdTests.swift
//  ChecklistdTests
//
//  Created by Arc Vorin on 2026-07-12.
//

import Foundation
import Testing
import VersionedCodable
@testable import Checklistd

@MainActor
struct ChecklistdTests {
    @Test func parserInterpolatesVariables() throws {
        let output = try Parser.interpolate(
            "Hello {{ name }}, you have {{count}} tasks.",
            variables: [
                "name": .string(value: "Arc"),
                "count": .int(int: 3)
            ]
        )
        
        #expect(output == "Hello Arc, you have 3 tasks.")
    }
    
    @Test func parserInterpolatesVariableTypes() throws {
        let date = Date(timeIntervalSince1970: 0)
        let output = try Parser.interpolate(
            "{{string}} {{date}} {{int}} {{bool}} {{float}}",
            variables: [
                "string": .string(value: "value"),
                "date": .date(date: date),
                "int": .int(int: 42),
                "bool": .bool(bool: true),
                "float": .float(float: 3.5)
            ]
        )
        
        #expect(output == "value \(Variable.date(date: date).interpolatedValue) 42 true 3.5")
    }
    
    @Test func parserThrowsForMissingVariable() throws {
        #expect(throws: Parser.ParserError.missingVariable("name")) {
            try Parser.interpolate("Hello {{ name }}", variables: [:])
        }
    }
    
    @Test func parserThrowsForMalformedTemplates() throws {
        #expect(throws: Parser.ParserError.unterminatedVariable) {
            try Parser.interpolate("Hello {{ name", variables: [:])
        }
        
        #expect(throws: Parser.ParserError.unexpectedClosingTag) {
            try Parser.interpolate("Hello name }}", variables: [:])
        }
        
        #expect(throws: Parser.ParserError.emptyVariableName) {
            try Parser.interpolate("Hello {{ }}", variables: [:])
        }
    }
    
    @Test func textStepComputesInterpolatedMessage() {
        let step = TextStep(id: "greeting", message: "Hello {{ name }}")
        let computedStep = step.compute(variables: ["name": .string(value: "Arc")])
        let computedTextStep = computedStep as? TextStep
        
        #expect(computedTextStep?.message == "Hello Arc")
    }
    
    @Test func flatProgramSampleDecodesValidatesAndCreatesExecution() throws {
        let program = try decodeBundledSampleProgram()
        
        try program.validate()
        #expect(program.steps.count == 22)
        #expect(program.steps.first?.step is InputStep)
        #expect(program.steps.last?.step.id == "step-vortex")
        
        var execution = Execution(program: program)
        try execution.run()
        #expect(execution.programCounter == "filtering-question")
        #expect(execution.activeSteps.count == 1)
    }
    
    @Test func flatStepAndInputShapesDecode() throws {
        let program = try decodeBundledSampleProgram()
        let inputSteps = program.steps.compactMap { $0.step as? InputStep }
        
        #expect(inputSteps.contains { if case .text = $0.inputKind { true } else { false } })
        #expect(inputSteps.contains { if case .float(0.3, 80, nil) = $0.inputKind { true } else { false } })
        #expect(inputSteps.contains { if case .float(nil, nil, let options) = $0.inputKind { options == [0.5, 0.7, 1] } else { false } })
        #expect(inputSteps.contains { if case .bool = $0.inputKind { true } else { false } })
        
        #expect(inputSteps.allSatisfy { $0.value == nil })
        
        let variableKinds = inputSteps.compactMap(\.defaultValue).map { $0.storageMediumRepresentation() }
        #expect(variableKinds.contains(.float))
        #expect(variableKinds.contains(.bool))
    }
    
    @Test func flatConditionalExpressionsDecodeAndEvaluate() throws {
        let decoder = JSONDecoder.checklistd
        let variables: [String: Variable] = [
            "score": .float(float: 42),
            "enabled": .bool(bool: true),
            "role": .string(value: "Engineer"),
            "deadline": .date(date: try Self.decodeDate("2026-03-15")),
            "reviewDate": .date(date: try Self.decodeDate("2026-06-20"))
        ]
        
        let numeric = try decoder.decode(
            ConditionalExpression.self,
            from: Data(#"{"op":"greaterThan","type":"numeric","lhs":{"var":"score"},"rhs":40,"orEqual":false}"#.utf8)
        )
        #expect(try numeric.evaluate(variables: variables))
        
        let boolean = try decoder.decode(
            ConditionalExpression.self,
            from: Data(#"{"op":"boolean","value":{"var":"enabled"}}"#.utf8)
        )
        #expect(try boolean.evaluate(variables: variables))
        
        let logic = try decoder.decode(
            ConditionalExpression.self,
            from: Data(#"{"op":"and","expressions":[{"op":"equal","type":"string","lhs":{"var":"role"},"rhs":"Engineer"},{"op":"not","expression":{"op":"equal","type":"string","lhs":{"var":"role"},"rhs":"Designer"}}]}"#.utf8)
        )
        #expect(try logic.evaluate(variables: variables))
        
        let dates = try decoder.decode(
            ConditionalExpression.self,
            from: Data(#"{"op":"and","expressions":[{"op":"before","lhs":{"var":"deadline"},"rhs":{"var":"reviewDate"},"orEqual":true},{"op":"after","lhs":{"var":"reviewDate"},"rhs":{"date":"2026-01-01"}},{"op":"sameDay","lhs":{"var":"reviewDate"},"rhs":{"date":"2026-06-20"}}]}"#.utf8)
        )
        #expect(try dates.evaluate(variables: variables))
    }
    
    @Test func programEncodingOmitsRuntimeStepState() throws {
        let program = try decodeBundledSampleProgram()
        let data = try JSONEncoder.checklistd.encode(program)
        let json = try #require(String(data: data, encoding: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let steps = try #require(object["steps"] as? [[String: Any]])
        let deadVolumeStep = try #require(steps.first { $0["key"] as? String == "Vdead" })
        let deadVolumeInput = try #require(deadVolumeStep["input"] as? [String: Any])
        let deadVolumeOptions = try #require(deadVolumeInput["options"] as? [String: Any])
        
        #expect(json.contains(#""defaultValue""#))
        #expect(deadVolumeOptions["type"] as? String == "float")
        #expect(deadVolumeOptions["values"] as? [Double] == [0.5, 0.7, 1])
        #expect(steps.allSatisfy { $0["computedValue"] == nil })
        #expect(steps.allSatisfy { $0["result"] == nil })
        #expect(steps.allSatisfy { $0["value"] == nil })
    }
    
    @Test func activeStepEncodingStoresRuntimeStepState() throws {
        let program = try decodeBundledSampleProgram()
        let inputStep = try #require(program.steps.compactMap { $0.step as? InputStep }.first)
        var runtimeInputStep = inputStep
        runtimeInputStep.value = .bool(bool: true)
        var activeStep = ActiveStep(stepEnvelope: StepEnvelope(step: inputStep))
        activeStep.computedStep = StepEnvelope(step: runtimeInputStep)
        
        let data = try JSONEncoder.checklistd.encode(activeStep)
        let json = try #require(String(data: data, encoding: .utf8))
        
        #expect(json.contains(#""defaultValue""#))
        #expect(json.contains(#""value":true"#))
    }
    
    @Test func executionEncodingIncludesRequiredAuditMetadata() throws {
        let program = try decodeBundledSampleProgram()
        let createdAt = try Self.decodeDate("2026-07-19T12:00:00Z")
        let updatedAt = try Self.decodeDate("2026-07-19T12:30:00Z")
        let execution = Execution(
            id: "execution-id",
            name: "Morning prep",
            createdByName: "Arc Vorin",
            createdByEmail: "arc@example.com",
            createdAt: createdAt,
            updatedAt: updatedAt,
            program: program
        )
        
        let data = try JSONEncoder.checklistd.encode(execution)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        
        #expect(object["name"] as? String == "Morning prep")
        #expect(object["createdByName"] as? String == "Arc Vorin")
        #expect(object["createdByEmail"] as? String == "arc@example.com")
        #expect((object["createdAt"] as? String)?.contains("T12:00:00") == true)
        #expect((object["updatedAt"] as? String)?.contains("T12:30:00") == true)
        
        let decoded = try JSONDecoder.checklistd.decode(Execution.self, from: data)
        #expect(decoded.name == "Morning prep")
        #expect(decoded.createdByName == "Arc Vorin")
        #expect(decoded.createdByEmail == "arc@example.com")
        #expect(decoded.createdAt == createdAt)
        #expect(decoded.updatedAt == updatedAt)
    }
    
    @Test func executionAuditMetadataIsRequired() throws {
        let program = try decodeBundledSampleProgram()
        let data = try JSONEncoder.checklistd.encode(Execution(id: "missing-audit", program: program))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "createdByName")
        let missingMetadataData = try JSONSerialization.data(withJSONObject: object)
        
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder.checklistd.decode(Execution.self, from: missingMetadataData)
        }
    }
    
    @Test func legacyStepWrapperDoesNotDecode() throws {
        let legacyJSON = Data(
            """
            {
                "version": 1,
                "title": "Legacy",
                "authorName": "Arc",
                "description": "Old wrapper shape",
                "steps": [
                    {
                        "type": "text",
                        "step": {
                            "type": "text",
                            "metadata": { "id": "old" },
                            "message": "Old shape"
                        }
                    }
                ]
            }
            """.utf8
        )
        
        var didThrow = false
        do {
            _ = try JSONDecoder.checklistd.decode(versioned: Program.self, from: legacyJSON)
            Issue.record("Legacy step wrapper unexpectedly decoded.")
        } catch {
            didThrow = true
        }
        
        #expect(didThrow)
    }
    
    private func decodeBundledSampleProgram() throws -> Program {
        let testFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("test.json")
        let data = try Data(contentsOf: testFileURL)
        return try JSONDecoder.checklistd.decode(versioned: Program.self, from: data)
    }
    
    private static func decodeDate(_ value: String) throws -> Date {
        try JSONDecoder.checklistd.decode(Date.self, from: Data(#""\#(value)""#.utf8))
    }
}
