//
//  ChecklistdTests.swift
//  ChecklistdTests
//
//  Created by Arc Vorin on 2026-07-12.
//

import Foundation
import Testing
@testable import Checklistd

struct ChecklistdTests {
    @Test func parserInterpolatesVariables() throws {
        let output = try Parser.interpolate(
            "Hello {{ name }}, you have {{count}} tasks.",
            variables: [
                "name": .string(value: "Javier"),
                "count": .int(int: 3)
            ]
        )
        
        #expect(output == "Hello Javier, you have 3 tasks.")
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
        
        #expect(output == "value 1970-01-01T00:00:00Z 42 true 3.5")
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
        let step = TextStep(message: "Hello {{ name }}")
        let computedStep = step.compute(variables: ["name": .string(value: "Javier")])
        let computedTextStep = computedStep as? TextStep
        
        #expect(computedTextStep?.message == "Hello Javier")
    }
}
