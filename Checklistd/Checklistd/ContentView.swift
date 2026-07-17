//
//  ContentView.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-12.
//

import SwiftUI

struct ContentView: View {
    @Binding var execution: Execution?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            activeStepsList
        }
        .padding()
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(execution?.program.authorName ?? "")
                .font(.callout)
            Text(execution?.program.title ?? "No program loaded")
                .font(.title)
            Text(execution?.program.description ?? "")
                .font(.caption)
        }
    }
    
    @ViewBuilder
    private var activeStepsList: some View {
        if let execution {
            if execution.activeSteps.isEmpty {
                Text(execution.isCompleted ? "Program complete" : "No active steps")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                let visibleSteps = visibleActiveSteps(for: execution)
                
                ScrollViewReader { proxy in
                    List(visibleSteps, id: \.offset) { index, activeStep in
                        StepView(
                            activeStep: activeStep,
                            activeStepIndex: index,
                            isCurrentStep: index == execution.activeSteps.indices.last && !execution.isCompleted,
                            execution: $execution
                        )
                    }
                    .listStyle(.plain)
                    .onAppear {
                        scrollToBottom(proxy: proxy, visibleSteps: visibleSteps, animated: false)
                    }
                    .onChange(of: visibleStepSignature(for: execution)) {
                        scrollToBottom(proxy: proxy, visibleSteps: visibleSteps, animated: true)
                    }
                }
            }
        } else {
            Text("No execution loaded")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
    
    private func visibleActiveSteps(for execution: Execution) -> [(offset: Int, element: ActiveStep)] {
        Array(execution.activeSteps.enumerated()).filter { _, activeStep in
            activeStep.computedStep.step.visible
        }
    }
    
    private func visibleStepSignature(for execution: Execution) -> String {
        visibleActiveSteps(for: execution)
            .map { index, activeStep in
                "\(index):\(activeStep.computedStep.step.id):\(activeStep.isCompleted)"
            }
            .joined(separator: "|")
    }
    
    private func scrollToBottom(
        proxy: ScrollViewProxy,
        visibleSteps: [(offset: Int, element: ActiveStep)],
        animated: Bool
    ) {
        guard let lastStepId = visibleSteps.last?.offset else { return }
        
        if animated {
            withAnimation {
                proxy.scrollTo(lastStepId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastStepId, anchor: .bottom)
        }
    }
}

struct StepView: View {
    let activeStep: ActiveStep
    let activeStepIndex: Int
    let isCurrentStep: Bool
    @Binding var execution: Execution?
    @State private var isConfirmingReopen = false
    
    private var step: Step {
        activeStep.computedStep.step
    }
    
    private var canCompleteCurrentStep: Bool {
        guard isCurrentStep else { return false }
        return (try? step.canComplete(with: execution?.variables ?? [:])) == true
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            
            Button {
                if canCompleteCurrentStep {
                    try? execution?.completeStep()
                }
            } label: {
                Image(systemName: activeStep.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(activeStep.isCompleted ? .clear : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(!activeStep.isCompleted && !canCompleteCurrentStep)
            .padding(.top, 6)
            stepContent
                .opacity(activeStep.isCompleted ? 0.6 : 1)
        }
        .onTapGesture {
            if activeStep.isCompleted {
                isConfirmingReopen = true
            } else if canCompleteCurrentStep {
                try? execution?.completeStep()
            }
        }
        .confirmationDialog(
            "Go back to this step?",
            isPresented: $isConfirmingReopen,
            titleVisibility: .visible
        ) {
            Button("Go Back", role: .destructive) {
                try? execution?.reopenStep(at: activeStepIndex)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all later rows and return execution to this step.")
        }
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch step.type {
            case .text:
                if let textStep = step as? TextStep {
                    TextStepView(step: textStep, isCompleted: activeStep.isCompleted)
                } else {
                    UnsupportedStepView(step: step)
                }
            case .input:
                if let inputStep = step as? InputStep {
                    InputStepView(step: inputStep, isCompleted: activeStep.isCompleted, isCurrentStep: isCurrentStep, execution: $execution)
                } else {
                    UnsupportedStepView(step: step)
                }
            case .compute:
                UnsupportedStepView(step: step)
            case .conditional:
            UnsupportedStepView(step: step)
        }
    }
}

struct TextStepView: View {
    let step: TextStep
    let isCompleted: Bool
    
    var body: some View {
        Text(step.message)
            .padding(.vertical, 4)
            .strikethrough(isCompleted)
    }
}

struct InputStepView: View {
    let step: InputStep
    let isCompleted: Bool
    let isCurrentStep: Bool
    @Binding var execution: Execution?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step.label ?? step.name)
                .font(.headline)
                .strikethrough(isCompleted)
            inputControl
                .disabled(!isCurrentStep)
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var inputControl: some View {
        switch step.inputKind {
            case .text:
                TextField("Value", text: textBinding)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.sentences)
            case .int:
                TextField("Value", text: intBinding)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
            case .float:
                TextField("Value", text: floatBinding)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
            case .bool:
                Toggle("Value", isOn: boolBinding)
            case .date:
                dateInputControl
            case .choice(let options, let allowOther):
                choiceInputControl(options: options, allowOther: allowOther)
        }
    }
    
    @ViewBuilder
    private var dateInputControl: some View {
        switch step.inputKind {
            case .date(_, _, let options) where options?.isEmpty == false:
                Picker("Value", selection: dateBinding) {
                    ForEach(options!, id: \.self) { option in
                        Text(option.formatted(date: .abbreviated, time: .omitted))
                            .tag(option)
                    }
                }
            case .date:
                DatePicker("Value", selection: dateBinding, in: dateRange, displayedComponents: .date)
            default:
                EmptyView()
        }
    }
    
    @ViewBuilder
    private func choiceInputControl(options: [String], allowOther: Bool) -> some View {
        if allowOther {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Value", selection: choicePickerBinding(options: options)) {
                    Text("Custom").tag("")
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                TextField("Value", text: textBinding)
                    .textFieldStyle(.roundedBorder)
            }
        } else {
            Picker("Value", selection: textBinding) {
                Text("Select").tag("")
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        }
    }
    
    private var textBinding: Binding<String> {
        Binding(
            get: { step.value?.interpolatedValue ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    clearVariable()
                } else {
                    setVariable(.string(value: newValue))
                }
            }
        )
    }
    
    private func choicePickerBinding(options: [String]) -> Binding<String> {
        Binding(
            get: {
                let value = step.value?.interpolatedValue ?? ""
                return options.contains(value) ? value : ""
            },
            set: { newValue in
                guard !newValue.isEmpty else { return }
                setVariable(.string(value: newValue))
            }
        )
    }
    
    private var intBinding: Binding<String> {
        Binding(
            get: { step.value?.interpolatedValue ?? "" },
            set: { newValue in
                guard let value = Int(newValue) else {
                    clearVariable()
                    return
                }
                setVariableIfValid(.int(int: value))
            }
        )
    }
    
    private var floatBinding: Binding<String> {
        Binding(
            get: { step.value?.interpolatedValue ?? "" },
            set: { newValue in
                guard let value = Float(newValue) else {
                    clearVariable()
                    return
                }
                setVariableIfValid(.float(float: value))
            }
        )
    }
    
    private var boolBinding: Binding<Bool> {
        Binding(
            get: {
                if case .bool(let value) = step.value {
                    return value
                }
                return false
            },
            set: { setVariable(.bool(bool: $0)) }
        )
    }
    
    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                if case .date(let value) = step.value {
                    return value
                }
                return Date()
            },
            set: { setVariableIfValid(.date(date: $0)) }
        )
    }
    
    private var dateRange: ClosedRange<Date> {
        guard case .date(let start, let end, _) = step.inputKind else {
            return Date.distantPast...Date.distantFuture
        }
        return (start ?? Date.distantPast)...(end ?? Date.distantFuture)
    }
    
    private func setVariableIfValid(_ value: Variable) {
        guard (try? step.inputKind.validate(value)) != nil else {
            clearVariable()
            return
        }
        setVariable(value)
    }
    
    private func setVariable(_ value: Variable) {
        guard var currentExecution = execution else { return }
        try? currentExecution.setVariable(name: step.key, value: value)
        execution = currentExecution
    }
    
    private func clearVariable() {
        guard var currentExecution = execution else { return }
        try? currentExecution.clearVariable(name: step.key)
        execution = currentExecution
    }
}

struct UnsupportedStepView: View {
    let step: Step
    
    var body: some View {
        Text("Unsupported step: \(step.type.rawValue)")
            .foregroundStyle(.secondary)
    }
}

#Preview {
    ContentView(execution: .constant(nil))
}
