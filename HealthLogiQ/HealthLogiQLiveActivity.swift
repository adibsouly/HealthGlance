//
//  HealthLogiQLiveActivity.swift
//  HealthLogiQ
//
//  Created by Adib Souly on 2026-06-18.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct HealthLogiQAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct HealthLogiQLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HealthLogiQAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension HealthLogiQAttributes {
    fileprivate static var preview: HealthLogiQAttributes {
        HealthLogiQAttributes(name: "World")
    }
}

extension HealthLogiQAttributes.ContentState {
    fileprivate static var smiley: HealthLogiQAttributes.ContentState {
        HealthLogiQAttributes.ContentState(emoji: "😀")
     }

     fileprivate static var starEyes: HealthLogiQAttributes.ContentState {
         HealthLogiQAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: HealthLogiQAttributes.preview) {
   HealthLogiQLiveActivity()
} contentStates: {
    HealthLogiQAttributes.ContentState.smiley
    HealthLogiQAttributes.ContentState.starEyes
}
