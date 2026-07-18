//
//  PageDotsView.swift
//  Fond
//
//  Two-face indicator for the Ember Folio card.
//

import SwiftUI

struct PageDotsView: View {
    let count: Int
    let activeIndex: Int
    var activeColor: Color = FondColors.amber

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<min(count, 2), id: \.self) { index in
                Circle()
                    .fill(index == activeIndex ? activeColor : FondColors.inkSecondary)
                    .frame(
                        width: index == activeIndex ? 7 : 4,
                        height: index == activeIndex ? 7 : 4
                    )
            }
        }
        .animation(.fondQuick, value: activeIndex)
    }
}
