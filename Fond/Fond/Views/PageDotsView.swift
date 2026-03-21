//
//  PageDotsView.swift
//  Fond
//
//  Custom page indicator with variable-width active dot.
//  Active dot is a 10pt capsule tinted to match content color.
//  Inactive dots are 4pt circles.
//

import SwiftUI

struct PageDotsView: View {
    let count: Int
    let activeIndex: Int
    var activeColor: Color = FondColors.amber

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                if index == activeIndex {
                    Capsule()
                        .fill(activeColor)
                        .frame(width: 10, height: 4)
                } else {
                    Circle()
                        .fill(FondColors.textSecondary.opacity(0.15))
                        .frame(width: 4, height: 4)
                }
            }
        }
        .animation(.fondQuick, value: activeIndex)
    }
}
