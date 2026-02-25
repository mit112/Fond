//
//  widgetsBundle.swift
//  widgets
//
//  Widget bundle entry point.
//  Each Widget is a separate entry so users can place them independently.
//

import WidgetKit
import SwiftUI

@main
struct FondWidgetBundle: WidgetBundle {
    var body: some Widget {
        FondWidget()
        FondDateWidget()
        FondDistanceWidget()
    }
}
