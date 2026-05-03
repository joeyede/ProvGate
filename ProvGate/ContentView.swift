//
//  ContentView.swift
//  ProvGate
//
//  Created by Joey Edelstein on 02/05/2026.
//

import SwiftUI

struct ContentView: View {
    @Environment(MQTTManager.self) private var mqtt
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch mqtt.connectionState {
            case .initializing, .connecting:
                ConnectingView()
            case .disconnected:
                LoginView()
            case .reconnecting, .connected:
                GateControlView()
            }

            if let message = mqtt.notificationMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.8))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, 60)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: mqtt.notificationMessage != nil)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { mqtt.handleAppBecameActive() }
        }
    }
}

private struct ConnectingView: View {
    @Environment(MQTTManager.self) private var mqtt

    var body: some View {
        VStack(spacing: 20) {
            Text("Gate Control")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.accentColor)
            ProgressView()
                .scaleEffect(1.5)
                .padding(.top, 8)
            Text(mqtt.statusMessage)
                .foregroundStyle(.secondary)
            if mqtt.connectionState == .connecting {
                Text("Restoring your session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
