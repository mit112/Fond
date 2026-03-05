//
//  StatusPickerSheet.swift
//  Fond
//
//  Grid-based status picker, grouped by category.
//  Presented as a half-sheet from ConnectedView.
//
//  Design: 4-column grid with section headers.
//  One tap selects + dismisses. Haptic on selection.
//  Current status highlighted with amber glass tint.
//
//  Design reference: docs/02-design-direction.md
//

import SwiftUI

struct StatusPickerSheet: View {
    let currentStatus: UserStatus
    let onSelect: (UserStatus) -> Void

    @Environment(\.dismiss) private var dismiss

    // 4-column grid — each item is roughly 70pt wide
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 4
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(UserStatus.Category.allCases, id: \.self) { category in
                        statusSection(category)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .fondBackground()
            .navigationTitle("Your Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(FondColors.amber)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Section

    private func statusSection(_ category: UserStatus.Category) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            Text(category.rawValue.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(FondColors.textSecondary)
                .tracking(1.2)
                .padding(.leading, 4)

            // Status grid
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(category.statuses, id: \.self) { status in
                    statusCell(status)
                }
            }
        }
    }

    // MARK: - Cell

    private func statusCell(_ status: UserStatus) -> some View {
        let isSelected = status == currentStatus

        return Button {
            FondHaptics.statusChanged()
            onSelect(status)
            dismiss()
        } label: {
            VStack(spacing: 4) {
                Text(status.emoji)
                    .font(.title2)
                Text(status.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(
                        isSelected ? FondColors.text : FondColors.textSecondary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .fondGlassInteractive(
            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
            tinted: isSelected
        )
        .animation(.fondQuick, value: isSelected)
    }
}

// MARK: - Preview

#Preview {
    StatusPickerSheet(currentStatus: .available) { status in
        print("Selected: \(status)")
    }
}
