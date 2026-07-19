//
//  View+Extensions.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-19.
//
import SwiftUI

extension View {
    @ViewBuilder
    func checklistdInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

extension View {
    @ViewBuilder
    func checklistdExecutionPickerStyle() -> some View {
        #if os(iOS)
        pickerStyle(.wheel)
        #else
        pickerStyle(.menu)
        #endif
    }
}
