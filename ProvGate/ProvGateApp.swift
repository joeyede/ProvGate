//
//  ProvGateApp.swift
//  ProvGate
//
//  Created by Joey Edelstein on 02/05/2026.
//

import SwiftUI

@main
struct ProvGateApp: App {
    @State private var mqtt = MQTTManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(mqtt)
        }
    }
}
