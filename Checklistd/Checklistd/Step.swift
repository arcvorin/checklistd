//
//  Step.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-12.
//

import Foundation
import VersionedCodable
import Expression
enum StepType : String, Codable {
    case text
    case input
    case compute
    case conditional
    var metatype: Step.Type {
        switch self {
            case .text: return TextStep.self
            case .input: return InputStep.self
            case .compute: return ComputeStep.self
            case .conditional: return ConditionalStep.self
        }
        
    }
}

enum InputKind : Codable {
    case text
    case int(start: Int?, end: Int?)
    case bool
    case float(start: Double?, end: Double?)
    case date(start: Date?, end: Date?, options: [Date]?)
    case choice(options: [String], allowOther: Bool)
    
    func storageMediumRepresentation() -> StorageMedium {
        switch self {
            case .text: return .string
            case .int: return .int
            case .bool: return .bool
            case .float: return .float
            case .date: return .date
            case .choice: return .string
        }
    }
    
    func validate(_ variable: Variable) throws {
        guard variable.storageMediumRepresentation() == storageMediumRepresentation() else {
            throw ComputeError.variableStorageMismatch
        }
        
        switch (self, variable) {
            case (.text, .string(let value)):
                guard !value.isEmpty else { throw ComputeError.missingRequiredInput }
            case (.int(let start, let end), .int(let value)):
                if let start, value < start { throw ComputeError.inputOutOfBounds }
                if let end, value > end { throw ComputeError.inputOutOfBounds }
            case (.float(let start, let end), .float(let value)):
                let doubleValue = Double(value)
                if let start, doubleValue < start { throw ComputeError.inputOutOfBounds }
                if let end, doubleValue > end { throw ComputeError.inputOutOfBounds }
            case (.date(let start, let end, let options), .date(let value)):
                if let start, value < start { throw ComputeError.inputOutOfBounds }
                if let end, value > end { throw ComputeError.inputOutOfBounds }
                if let options, !options.contains(value) { throw ComputeError.invalidOption }
            case (.choice(let options, let allowOther), .string(let value)):
                guard !value.isEmpty else { throw ComputeError.missingRequiredInput }
                if !allowOther && !options.contains(value) { throw ComputeError.invalidOption }
            case (.bool, .bool):
                break
            default:
                throw ComputeError.variableStorageMismatch
        }
    }
}



protocol Step : Codable {
    var type: StepType { get }
    var metadata: StepMetadata { get }
    func compute(variables: [String: Variable]) throws -> Step
    func canComplete(with variables: [String: Variable]) throws -> Bool
    func getNextStep() -> String?
}

struct StepMetadata: Codable {
    var id: String
    var name: String
    var description: String?
    var visible: Bool
    
    init(id: String, name: String = "Untitled", description: String? = nil, visible: Bool = true) {
        self.id = id
        self.name = name
        self.description = description
        self.visible = visible
    }
    
    private enum CodingKeys: CodingKey {
        case id, name, description, visible
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.visible = try container.decodeIfPresent(Bool.self, forKey: .visible) ?? true
    }
}

extension Step {
    var id: String {
        metadata.id
    }
    var name: String {
        metadata.name
    }
    
    var description: String? {
        metadata.description
    }
    
    func getNextStep() -> String? {
        nil
    }
    var visible: Bool {
        metadata.visible
    }
    
    func canComplete(with variables: [String: Variable]) throws -> Bool {
        true
    }
    
}

enum ComputeError: Error {
    case variableStorageMismatch
    case missingRequiredInput
    case inputOutOfBounds
    case invalidOption
}

struct NumericExpression: Codable, ExpressibleByStringLiteral {
    var value: String
    
    init(_ value: String) {
        self.value = value
    }
    
    init(stringLiteral value: String) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(String.self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
    
    func variablesUsed() -> [String] {
        let expression = Expression(value)
        var seenVariables = Set<String>()
        
        return expression.symbols.compactMap { symbol -> String? in
            guard case .variable(let name) = symbol else { return nil }
            guard !seenVariables.contains(name) else { return nil }
            seenVariables.insert(name)
            return name
        }
    }
    
    func missingOrNonNumericVariables(in availableVariables: [String: Variable]) -> [String] {
        variablesUsed().filter { variableName in
            guard let variable = availableVariables[variableName] else { return true }
            return variable.numericValue == nil
        }
    }
    
    func canEvaluate(variables: [String: Variable]) -> Bool {
        missingOrNonNumericVariables(in: variables).isEmpty
    }
    
    func evaluate(variables: [String: Variable]) throws -> Float {
        guard canEvaluate(variables: variables) else {
            throw ComputeError.variableStorageMismatch
        }
        
        let constants = Dictionary(uniqueKeysWithValues: variablesUsed().map { variableName in
            (variableName, variables[variableName]!.numericValue!)
        })
        let expression = Expression(value, constants: constants)
        
        return Float(try expression.evaluate())
    }
}

struct TextStep: Step {
    var type = StepType.text
    var metadata: StepMetadata
    var message: String
    private var nextStepId: String?
    
    init(id: String, message: String, nextStepId: String? = nil) {
        self.type = .text
        self.metadata = StepMetadata(id: id)
        self.message = message
        self.nextStepId = nextStepId
    }
    
    func compute(variables: [String: Variable]) -> Step {
        var copy = self
        copy.message = (try? Parser.interpolate(message, variables: variables)) ?? message
        return copy
    }
    
    func getNextStep() -> String? {
        nextStepId
    }
}

struct InputStep: Step {
    var type = StepType.input
    var metadata: StepMetadata
    var inputKind: InputKind
    var label: String?
    var value: Variable?
    var key: String
    private var nextStepId: String
    
    func compute(variables: [String : Variable]) throws -> any Step {
        var copy = self
        copy.label = label != nil ? (try? Parser.interpolate(label!, variables: variables)) : nil
        if (variables.keys.contains(key)) {
            copy.value = variables[key]
        }
        guard let copyValue = copy.value else { return copy }
        try inputKind.validate(copyValue)
        return copy
    }
    
    func canComplete(with variables: [String: Variable]) throws -> Bool {
        let computedStep = try compute(variables: variables)
        guard let computedInputStep = computedStep as? InputStep else {
            return false
        }
        guard let value = computedInputStep.value else {
            throw ComputeError.missingRequiredInput
        }
        try inputKind.validate(value)
        return true
    }
    
    func getNextStep() -> String? {
        nextStepId
    }
}

indirect enum ConditionalExpression: Codable {
    
    enum VariableOrKindEnum: Codable {
        case variable(name: String)
        case string(value: String)
        case date(value: Date)
        case numeric(value: Float)
        case numericExpression(value: NumericExpression)
        case boolean(value: Bool)
        
        func stringValue(variables: [String: Variable]) throws -> String {
            switch self {
            case .variable(name: let name):
                guard let value = variables[name] else {
                    throw ConditionalExpressionError.variableNotFound(name: name)
                }
                guard value.storageMediumRepresentation() == .string else {
                    throw ConditionalExpressionError.variableWrongType(name: name, expected: "string", actual: value.storageMediumRepresentation().rawValue)
                }
                return value.interpolatedValue
            case .string(value: let value):
                return value
            case .boolean:
                throw ConditionalExpressionError.variableWrongType(name: "variable", expected: "string", actual: "boolean")
            case .date:
                throw ConditionalExpressionError.variableWrongType(name: "variable", expected: "string", actual: "date")
            case .numeric:
                throw ConditionalExpressionError.variableWrongType(name: "variable", expected: "string", actual: "numeric")
            case .numericExpression:
                throw ConditionalExpressionError.variableWrongType(name: "variable", expected: "string", actual: "numericExpression")
            }
        }
        
        func dateValue(variables: [String: Variable]) throws -> Date {
            switch self {
            case .variable(name: let name):
                guard let value = variables[name] else {
                    throw ConditionalExpressionError.variableNotFound(name: name)
                }
                guard value.storageMediumRepresentation() == .date else {
                    throw ConditionalExpressionError.variableWrongType(name: name, expected: "date", actual: value.storageMediumRepresentation().rawValue)
                }
                guard let dateValue = value.dateValue else {
                    throw ConditionalExpressionError.variableUnexpectedValue(expected: "date")
                }
                return dateValue
            case .date(value: let value):
                return value
            case .boolean:
                throw ConditionalExpressionError.wrongType(expected: "date", actual: "boolean")
            case .string:
                throw ConditionalExpressionError.wrongType(expected: "date", actual: "string")
            case .numeric:
                throw ConditionalExpressionError.wrongType(expected: "date", actual: "numeric")
            case .numericExpression:
                throw ConditionalExpressionError.variableWrongType(name: "variable", expected: "string", actual: "numericExpression")
            }
        }
        
        func numericValue(variables: [String: Variable]) throws -> Float {
            switch self {
                case .variable(name: let name):
                guard let value = variables[name] else {
                    throw ConditionalExpressionError.variableNotFound(name: name)
                }
                guard value.storageMediumRepresentation() == .float || value.storageMediumRepresentation() == .int else {
                        throw ConditionalExpressionError.variableWrongType(name: name, expected: "numeric", actual: value.storageMediumRepresentation().rawValue)
                }
                guard let numericValue = value.numericValue else {
                    throw ConditionalExpressionError.variableUnexpectedValue(expected: "numeric")
                }
                return Float(numericValue)
                case .numeric(value: let value):
                return value
            case .numericExpression(value: let value):
                return try value.evaluate(variables: variables)
            case .boolean:
                throw ConditionalExpressionError.wrongType(expected: "numeric", actual: "boolean")
            case .string:
                throw ConditionalExpressionError.wrongType(expected: "numeric", actual: "string")
            case .date:
                throw ConditionalExpressionError.wrongType(expected: "numeric", actual: "date")
                
            }
        }
        
        func booleanValue(variables: [String: Variable]) throws -> Bool {
            switch self {
            case .variable(name: let name):
                guard let value = variables[name] else {
                    throw ConditionalExpressionError.variableNotFound(name: name)
                }
                guard value.storageMediumRepresentation() == .bool else {
                    throw ConditionalExpressionError.variableWrongType(name: name, expected: "boolean", actual: value.storageMediumRepresentation().rawValue)
                }
                guard let booleanValue = value.booleanValue else {
                    throw ConditionalExpressionError.variableUnexpectedValue(expected: "boolean")
                }
                return booleanValue
            case .boolean(value: let value):
                return value
            case .date:
                throw ConditionalExpressionError.wrongType(expected: "boolean", actual: "date")
            case .numeric:
                throw ConditionalExpressionError.wrongType(expected: "boolean", actual: "numeric")
            case .string:
                throw ConditionalExpressionError.wrongType(expected: "boolean", actual: "string")
            case .numericExpression:
                throw ConditionalExpressionError.variableWrongType(name: "variable", expected: "string", actual: "numericExpression")

            }
        }
    }
    
    case greaterThan(type: String, lhs: VariableOrKindEnum, rhs: VariableOrKindEnum, orEqual: Bool = false)
    case lessThan(type: String, lhs: VariableOrKindEnum, rhs: VariableOrKindEnum, orEqual: Bool = false)
    case equal(type: String, lhs: VariableOrKindEnum, rhs: VariableOrKindEnum)
    case valueIn(type: String, lhs: VariableOrKindEnum, rhs: [VariableOrKindEnum])
    case and(expressions: [ConditionalExpression])
    case or(expressions: [ConditionalExpression])
    case negate(expression: ConditionalExpression)
    case boolean(value: VariableOrKindEnum)
    case before(lhs: VariableOrKindEnum, rhs: VariableOrKindEnum, orEqual: Bool = false)
    case after(lhs: VariableOrKindEnum, rhs: VariableOrKindEnum, orEqual: Bool = false)
    case sameDay(lhs: VariableOrKindEnum, rhs: VariableOrKindEnum)
    
    enum ConditionalExpressionError: Error {
        case variableUnexpectedValue(expected: String)
        case wrongType(expected: String, actual: String)
        case variableNotFound(name: String)
        case variableWrongType(name: String, expected: String, actual: String)
        case unexpectedComparison(lhs: String, rhs: String)
    }
    
    func evaluate(variables: [String: Variable]) throws -> Bool {
        switch self {
        case .boolean(value: let val):
            return try val.booleanValue(variables: variables)
        case .negate(expression: let expression):
            return !(try expression.evaluate(variables: variables))
        case .and(expressions: let expressions):
            return try expressions.allSatisfy({try $0.evaluate(variables: variables)})
        case .or(expressions: let expressions):
            return try expressions.contains(where: { try $0.evaluate(variables: variables)})
        case .greaterThan(type: let type, lhs: let lhs, rhs: let rhs, orEqual: let orEqual):
            switch type {
                case "string":
                let a = try lhs.stringValue(variables: variables)
                let b = try rhs.stringValue(variables: variables)
                return a > b || (orEqual && a == b)
                case "date":
                let a = try lhs.dateValue(variables: variables)
                let b = try rhs.dateValue(variables: variables)
                return a > b || (orEqual && a == b)
                case "boolean":
                let a = try lhs.booleanValue(variables: variables)
                let b = try rhs.booleanValue(variables: variables)
                return !a && b || (orEqual && a == b)
                case "numeric":
                let a = try lhs.numericValue(variables: variables)
                let b = try rhs.numericValue(variables: variables)
                return a > b || (orEqual && a == b)
                default:
                throw ConditionalExpressionError.unexpectedComparison(lhs: "\(lhs)", rhs: "\(rhs)")
            }
        case .lessThan(type: let type, lhs: let lhs, rhs: let rhs, orEqual: let orEqual):
            switch type {
                case "string":
                let a = try lhs.stringValue(variables: variables)
                let b = try rhs.stringValue(variables: variables)
                return a < b || (orEqual && a == b)
                case "date":
                let a = try lhs.dateValue(variables: variables)
                let b = try rhs.dateValue(variables: variables)
                return a < b || (orEqual && a == b)
                case "boolean":
                let a = try lhs.booleanValue(variables: variables)
                let b = try rhs.booleanValue(variables: variables)
                return !a && b || (orEqual && a == b)
                case "numeric":
                let a = try lhs.numericValue(variables: variables)
                let b = try rhs.numericValue(variables: variables)
                return a < b || (orEqual && a == b)
                default:
                throw ConditionalExpressionError.unexpectedComparison(lhs: "\(lhs)", rhs: "\(rhs)")
            }
        case .equal(type: let type, lhs: let lhs, rhs: let rhs):
            switch type {
                case "string":
                let a = try lhs.stringValue(variables: variables)
                let b = try rhs.stringValue(variables: variables)
                return a == b
                case "date":
                let a = try lhs.dateValue(variables: variables)
                let b = try rhs.dateValue(variables: variables)
                return a == b
                case "boolean":
                let a = try lhs.booleanValue(variables: variables)
                let b = try rhs.booleanValue(variables: variables)
                return a == b
                case "numeric":
                let a = try lhs.numericValue(variables: variables)
                let b = try rhs.numericValue(variables: variables)
                return a == b
                default:
                throw ConditionalExpressionError.unexpectedComparison(lhs: "\(lhs)", rhs: "\(rhs)")
            }
        case .valueIn(type: let type, lhs: let lhs, rhs: let rhs):
            switch type {
                case "string":
                let a = try lhs.stringValue(variables: variables)
                let b = try rhs.map({try $0.stringValue(variables: variables)})
                return b.contains(a)
                case "date":
                let a = try lhs.dateValue(variables: variables)
                let b = try rhs.map({try $0.dateValue(variables: variables)})
                return b.contains(a)
                case "boolean":
                let a = try lhs.booleanValue(variables: variables)
                let b = try rhs.map({try $0.booleanValue(variables: variables)})
                return b.contains(a)
                case "numeric":
                let a = try lhs.numericValue(variables: variables)
                let b = try rhs.map({try $0.numericValue(variables: variables)})
                return b.contains(a)
                default:
                throw ConditionalExpressionError.unexpectedComparison(lhs: "\(lhs)", rhs: "\(rhs)")
            }
        case .before(lhs: let lhs, rhs: let rhs, orEqual: let orEqual):
            let lhsDate = try lhs.dateValue(variables: variables)
            let rhsDate = try rhs.dateValue(variables: variables)
            return lhsDate.timeIntervalSince(rhsDate) < 0 || (orEqual && lhsDate.timeIntervalSince(rhsDate) == 0)
        case .after(lhs: let lhs, rhs: let rhs, orEqual: let orEqual):
            let lhsDate = try lhs.dateValue(variables: variables)
            let rhsDate = try rhs.dateValue(variables: variables)
            return lhsDate.timeIntervalSince(rhsDate) > 0 || (orEqual && lhsDate.timeIntervalSince(rhsDate) == 0)
        case .sameDay(lhs: let lhs, rhs: let rhs):
            return Calendar.current.isDate(try lhs.dateValue(variables: variables), inSameDayAs: try rhs.dateValue(variables: variables))
        }
    }
}

struct ConditionalStep: Step {
    var type = StepType.conditional
    var metadata: StepMetadata
    var condition: ConditionalExpression
    var trueStepId: String
    var falseStepId: String
    var result: Bool?
    func compute(variables: [String : Variable]) throws -> any Step {
        var copy = self
        copy.result = try condition.evaluate(variables: variables)
        return copy
    }
    
    func getNextStep() -> String? {
        guard let result = result else {
            return nil
        }
        return result ? trueStepId : falseStepId
    }
}

struct ComputeStep: Step {
    var type = StepType.compute
    var metadata: StepMetadata
    var key: String
    var expression: NumericExpression
    var computedValue: Float?
    var nextStepId: String
    
    func expressionVariables() -> [String] {
        expression.variablesUsed()
    }
    
    func missingOrNonNumericVariables(in availableVariables: [String: Variable]) -> [String] {
        expression.missingOrNonNumericVariables(in: availableVariables)
    }
    
    func canEvaluate(variables: [String: Variable]) -> Bool {
        expression.canEvaluate(variables: variables)
    }
    
    func compute(variables: [String: Variable]) throws -> any Step {
        var copy = self
        copy.computedValue = try expression.evaluate(variables: variables)
        return copy
    }
    
    func canComplete(with variables: [String : Variable]) throws -> Bool {
        canEvaluate(variables: variables)
    }
    
    func getNextStep() -> String? {
        nextStepId
    }
}


struct StepEnvelope {
    let step: Step
}

extension StepEnvelope: Codable {
    
    private enum CodingKeys: CodingKey {
        case type, step
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StepType.self, forKey: .type)
        self.step = try type.metatype.init(from: container.superDecoder(forKey: .step))
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(step.type, forKey: .type)
        try step.encode(to: container.superEncoder(forKey: .step))
    }
}
