//
//  ChecklistdApp.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-12.
//

import SwiftUI
import VersionedCodable

@main
struct ChecklistdApp: App {
    @State private var execution = Self.loadSampleExecution()
    
    var body: some Scene {
        WindowGroup {
            ContentView(execution: $execution)
        }
    }
    
    private static func loadSampleExecution() -> Execution? {
        do {
            guard let sampleURL = Bundle.main.url(forResource: "test", withExtension: "json") else {
                return nil
            }
            
            let data = try Data(contentsOf: sampleURL)
            let program = try JSONDecoder.checklistd.decode(versioned: Program.self, from: data)
            try program.validate()
            var execution = Execution(program: program)
            try execution.run()
            return execution
        } catch {
            assertionFailure("Failed to load sample program: \(error)")
            return nil
        }
    }
}

extension JSONDecoder {
    static var checklistd: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            
            if let date = DateFormatter.checklistdFullDate.date(from: value) {
                return date
            }
            
            if let date = ISO8601DateFormatter.checklistdDateTimeWithoutFractionalSeconds.date(from: value) {
                return date
            }
            
            if let date = ISO8601DateFormatter.checklistdDateTime.date(from: value) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 date string."
            )
        }
        return decoder
    }
}

extension JSONEncoder {
    static var checklistd: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateFormatter.checklistdFullDate.string(from: date))
        }
        return encoder
    }
}

private extension DateFormatter {
    static let checklistdFullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private extension ISO8601DateFormatter {
    static let checklistdDateTimeWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    static let checklistdDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
