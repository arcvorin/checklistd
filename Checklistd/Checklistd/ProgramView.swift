//
//  ContentView.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-12.
//

import SwiftUI

struct ProgramView: View {
    @Binding var execution: Execution?
    var currentActor: () -> GitCommitIdentity? = { nil }
    var isReadOnly: Bool = false
    var stepHistoryEvents: [String: ExecutionHistoryEvent] = [:]
    private let bottomAnchorID = "program-view-bottom-anchor"
    
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
//            Text(execution?.program.title ?? "No program loaded")
//                .font(.title)
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
                    List {
                        ForEach(visibleSteps, id: \.offset) { index, activeStep in
                            StepView(
                                activeStep: activeStep,
                                activeStepIndex: index,
                                isCurrentStep: index == execution.activeSteps.indices.last && !execution.isCompleted,
                                currentActor: currentActor,
                                isReadOnly: isReadOnly,
                                historyEvent: stepHistoryEvents[activeStep.stepEnvelope.step.id],
                                execution: $execution
                            )
                        }
                        
                        Color.clear
                            .frame(height: 1)
                            .listRowSeparator(.hidden)
                            .id(bottomAnchorID)
                    }
                    .listStyle(.plain)
                    .onAppear {
                        scrollToBottomAfterLayout(proxy: proxy, animated: false)
                    }
                    .onChange(of: visibleStepSignature(for: execution)) {
                        scrollToBottomAfterLayout(proxy: proxy, animated: true)
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
        animated: Bool
    ) {
        if animated {
            withAnimation {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }

    private func scrollToBottomAfterLayout(proxy: ScrollViewProxy, animated: Bool) {
        Task { @MainActor in
            await Task.yield()
            scrollToBottom(proxy: proxy, animated: animated)
        }
    }
}

struct StepView: View {
    let activeStep: ActiveStep
    let activeStepIndex: Int
    let isCurrentStep: Bool
    let currentActor: () -> GitCommitIdentity?
    let isReadOnly: Bool
    let historyEvent: ExecutionHistoryEvent?
    @Binding var execution: Execution?
    @State private var isConfirmingReopen = false
    
    private var step: Step {
        activeStep.computedStep.step
    }
    
    private var canCompleteCurrentStep: Bool {
        guard !isReadOnly else { return false }
        guard isCurrentStep else { return false }
        return (try? step.canComplete(with: execution?.variables ?? [:])) == true
    }

    private var isDifferentActor: Bool {
        guard let currentActor = currentActor() else { return false }
        guard !activeStep.actorName.isEmpty || !activeStep.actorEmail.isEmpty else { return false }
        return activeStep.actorName != currentActor.name || activeStep.actorEmail != currentActor.email
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            
            Button {
                completeCurrentStepIfPossible()
            } label: {
                Image(systemName: activeStep.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(activeStep.isCompleted ? .clear : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(isReadOnly || (!activeStep.isCompleted && !canCompleteCurrentStep))
            .opacity(isReadOnly ? 0.45 : 1)
            .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                stepContent
                    .opacity(activeStep.isCompleted ? 0.6 : 1)
                if let historyEvent {
                    Text(historyDescription(for: historyEvent))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if isReadOnly, !activeStep.actorName.isEmpty || !activeStep.actorEmail.isEmpty {
                    Text("By \(activeStep.actorName) <\(activeStep.actorEmail)>")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if isDifferentActor {
                    Text("By \(activeStep.actorName) <\(activeStep.actorEmail)>")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, isDifferentActor ? 8 : 0)
            .background(isDifferentActor ? Color.accentColor.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onTapGesture {
            if !isReadOnly && activeStep.isCompleted {
                isConfirmingReopen = true
            }
        }
        .confirmationDialog(
            "Go back to this step?",
            isPresented: $isConfirmingReopen,
            titleVisibility: .visible
        ) {
            Button("Go Back", role: .destructive) {
                try? execution?.reopenStep(at: activeStepIndex, actor: currentActor())
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
                    TextStepView(
                        step: textStep,
                        isCompleted: activeStep.isCompleted,
                        completeStep: completeCurrentStepIfPossible
                    )
                } else {
                    UnsupportedStepView(step: step)
                }
            case .input:
                if let inputStep = step as? InputStep {
                    InputStepView(
                        step: inputStep,
                        isCompleted: activeStep.isCompleted,
                        isCurrentStep: isCurrentStep,
                        currentActor: currentActor,
                        isReadOnly: isReadOnly,
                        completeStep: completeCurrentStepIfPossible,
                        execution: $execution
                    )
                } else {
                    UnsupportedStepView(step: step)
                }
            case .compute:
                UnsupportedStepView(step: step)
            case .conditional:
            UnsupportedStepView(step: step)
        }
    }
    
    private func historyDescription(for event: ExecutionHistoryEvent) -> String {
        "\(event.type.rawValue) by \(event.actorName) <\(event.actorEmail)> at \(event.timestamp.formatted(date: .abbreviated, time: .standard))"
    }

    private func completeCurrentStepIfPossible() {
        guard canCompleteCurrentStep else { return }
        try? execution?.completeStep(actor: currentActor())
    }
}

struct TextStepView: View {
    let step: TextStep
    let isCompleted: Bool
    let completeStep: () -> Void
    
    var body: some View {
        if isCompleted {
            Text(step.message)
                .padding(.vertical, 4)
                .strikethrough(true)
        } else {
            Text(step.message)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    completeStep()
                }
        }
    }
}

struct InputStepView: View {
    let step: InputStep
    let isCompleted: Bool
    let isCurrentStep: Bool
    let currentActor: () -> GitCommitIdentity?
    let isReadOnly: Bool
    let completeStep: () -> Void
    @Binding var execution: Execution?
    @State private var intDraft = ""
    @State private var floatDraft = ""
    @FocusState private var focusedNumericField: NumericField?

    private enum NumericField: Hashable {
        case int
        case float
    }

    private var canEditInput: Bool {
        !isReadOnly && isCurrentStep && !isCompleted
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            label
            inputControl
                .disabled(isReadOnly || !isCurrentStep)
        }
        .padding(.vertical, 4)
        .onAppear {
            syncNumericDraftsFromStep()
        }
        .onChange(of: step.value?.interpolatedValue ?? "") {
            syncNumericDraftsFromStep()
        }
        .onChange(of: focusedNumericField) {
            if focusedNumericField != .int {
                commitIntDraft(resyncInvalidDraft: true)
            }
            if focusedNumericField != .float {
                commitFloatDraft(resyncInvalidDraft: true)
            }
        }
        .onDisappear {
            commitIntDraft(resyncInvalidDraft: true)
            commitFloatDraft(resyncInvalidDraft: true)
        }
    }

    @ViewBuilder
    private var label: some View {
        if isCompleted {
            Text(step.label ?? step.name)
                .font(.headline)
                .strikethrough(true)
        } else {
            Text(step.label ?? step.name)
                .font(.headline)
                .contentShape(Rectangle())
                .onTapGesture {
                    completeStep()
                }
        }
    }
    
    @ViewBuilder
    private var inputControl: some View {
        switch step.inputKind {
            case .text:
                TextField("Value", text: textBinding)
                    .textFieldStyle(.roundedBorder)
                    .checklistdTextInputAutocapitalization()
            case .int(_, _, let options) where options?.isEmpty == false:
                Picker("Value", selection: intPickerBinding(options: options!)) {
                    Text("Select").tag(nil as Int?)
                    ForEach(options!, id: \.self) { option in
                        Text(String(option)).tag(Optional(option))
                    }
                }
                .pickerStyle(.menu)
            case .int:
                TextField("Value", text: $intDraft)
                    .textFieldStyle(.roundedBorder)
                    .checklistdKeyboardType(.numberPad)
                    .focused($focusedNumericField, equals: .int)
                    .onChange(of: intDraft) {
                        guard focusedNumericField == .int else { return }
                        commitIntDraft(resyncInvalidDraft: false)
                    }
                    .onSubmit {
                        commitIntDraft(resyncInvalidDraft: true)
                    }
            case .float(_, _, let options) where options?.isEmpty == false:
                Picker("Value", selection: floatPickerBinding(options: options!)) {
                    Text("Select").tag(nil as Float?)
                    ForEach(options!, id: \.self) { option in
                        Text(String(option)).tag(Optional(option))
                    }
                }
                .pickerStyle(.menu)
            case .float:
                TextField("Value", text: $floatDraft)
                    .textFieldStyle(.roundedBorder)
                    .checklistdKeyboardType(.decimalPad)
                    .focused($focusedNumericField, equals: .float)
                    .onChange(of: floatDraft) {
                        guard focusedNumericField == .float else { return }
                        commitFloatDraft(resyncInvalidDraft: false)
                    }
                    .onSubmit {
                        commitFloatDraft(resyncInvalidDraft: true)
                    }
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
                .pickerStyle(.menu)
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
                .pickerStyle(.menu)
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
            .pickerStyle(.menu)
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
    
    private func intPickerBinding(options: [Int]) -> Binding<Int?> {
        Binding(
            get: {
                guard case .int(let value) = step.value, options.contains(value) else {
                    return nil
                }
                return value
            },
            set: { newValue in
                guard let newValue else {
                    clearVariable()
                    return
                }
                setVariable(.int(int: newValue))
            }
        )
    }
    
    private func floatPickerBinding(options: [Float]) -> Binding<Float?> {
        Binding(
            get: {
                guard case .float(let value) = step.value, options.contains(value) else {
                    return nil
                }
                return value
            },
            set: { newValue in
                guard let newValue else {
                    clearVariable()
                    return
                }
                setVariable(.float(float: newValue))
            }
        )
    }

    private func syncNumericDraftsFromStep() {
        if focusedNumericField != .int {
            intDraft = step.value?.interpolatedValue ?? ""
        }
        if focusedNumericField != .float {
            floatDraft = step.value?.interpolatedValue ?? ""
        }
    }

    private func commitIntDraft(resyncInvalidDraft: Bool) {
        guard canEditInput else { return }
        guard case .int = step.inputKind else { return }
        let draft = intDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else {
            clearVariable()
            return
        }
        guard let value = Int(draft) else {
            clearVariable()
            if resyncInvalidDraft {
                syncNumericDraftsFromStep()
            }
            return
        }
        setVariableIfValid(.int(int: value), resyncInvalidDraft: resyncInvalidDraft)
    }

    private func commitFloatDraft(resyncInvalidDraft: Bool) {
        guard canEditInput else { return }
        guard case .float = step.inputKind else { return }
        let draft = floatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else {
            clearVariable()
            return
        }
        guard let value = Float(draft) else {
            clearVariable()
            if resyncInvalidDraft {
                syncNumericDraftsFromStep()
            }
            return
        }
        setVariableIfValid(.float(float: value), resyncInvalidDraft: resyncInvalidDraft)
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
        setVariableIfValid(value, resyncInvalidDraft: true)
    }
    
    private func setVariableIfValid(_ value: Variable, resyncInvalidDraft: Bool) {
        guard (try? step.inputKind.validate(value)) != nil else {
            clearVariable()
            if resyncInvalidDraft {
                syncNumericDraftsFromStep()
            }
            return
        }
        setVariable(value)
    }
    
    private func setVariable(_ value: Variable) {
        guard canEditInput else { return }
        guard var currentExecution = execution else { return }
        try? currentExecution.setVariable(
            name: step.key,
            value: value,
            actor: currentActor(),
            inputStep: step
        )
        execution = currentExecution
    }
    
    private func clearVariable() {
        guard canEditInput else { return }
        guard var currentExecution = execution else { return }
        try? currentExecution.clearVariable(
            name: step.key,
            actor: currentActor(),
            inputStep: step
        )
        execution = currentExecution
    }
}

private enum ChecklistdKeyboardType {
    case numberPad
    case decimalPad
}

private extension View {
    @ViewBuilder
    func checklistdTextInputAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.sentences)
        #else
        self
        #endif
    }

    @ViewBuilder
    func checklistdKeyboardType(_ keyboardType: ChecklistdKeyboardType) -> some View {
        #if os(iOS)
        switch keyboardType {
        case .numberPad:
            self.keyboardType(.numberPad)
        case .decimalPad:
            self.keyboardType(.decimalPad)
        }
        #else
        self
        #endif
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
    ProgramView(execution: .constant(nil))
}
