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
    @FocusState private var isFocusingPassword: Bool

    private var canConnect: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Gate Control")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                Text("v\(Bundle.main.appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = mqtt.connectionError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { isFocusingPassword = true }

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
                .submitLabel(.go)
                .onSubmit { if canConnect { handleConnect() } }
                .focused($isFocusingPassword)
                .overlay(alignment: .trailing) {
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
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
        .frame(maxWidth: .infinity)
        } // ScrollView
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear {
            let saved = CredentialsStore().load()
            username = saved.username ?? ""
            password = saved.password ?? ""
            rememberMe = saved.rememberMe
        }
    }

    private func handleConnect() {
        let u = username.trimmingCharacters(in: .whitespaces)
        let p = password.trimmingCharacters(in: .whitespaces)
        mqtt.connect(username: u, password: p, rememberMe: rememberMe)
    }

}

