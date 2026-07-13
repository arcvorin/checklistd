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
            let program = try JSONDecoder().decode(versioned: Program.self, from: data)
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
