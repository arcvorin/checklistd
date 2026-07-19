//
//  LoadingExecutionView.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-19.
//

import SwiftUI

struct LoadingExecutionView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Execution")
        .checklistdInlineNavigationTitle()
    }
}
