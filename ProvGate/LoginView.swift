import SwiftUI

#Preview {
    LoginView()
        .environment(MQTTManager())
}

struct LoginView: View {
    @Environment(MQTTManager.self) private var mqtt
    @State private var username = ""
    @State private var password = ""
    @State private var rememberMe = false
    @State private var showPassword = false

    private var canConnect: Bool { !username.isEmpty && !password.isEmpty }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Gate Control")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                Text("v\(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if mqtt.statusMessage != "Enter credentials" {
                Text(mqtt.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(mqtt.statusMessage.lowercased().contains("fail") ? .red : .secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Group {
                    if showPassword {
                        TextField("Password", text: $password)
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .overlay(alignment: .trailing) {
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                    }
                }

                Toggle("Remember me", isOn: $rememberMe)
                    .tint(Color.accentColor)

                Button(action: handleConnect) {
                    Text("Connect")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canConnect ? Color.accentColor : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!canConnect)
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 20)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear {
            username = mqtt.savedUsername
            password = mqtt.savedPassword
            rememberMe = mqtt.savedRememberMe
        }
    }

    private func handleConnect() {
        mqtt.connect(username: username, password: password, rememberMe: rememberMe)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

