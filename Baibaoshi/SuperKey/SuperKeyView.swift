import SwiftUI

struct SuperKeyView: View {
    @EnvironmentObject private var recorder: RecorderService
    @State private var status = "按住说话"
    @State private var stage: Stage = .idle
    @State private var transcript = ""
    @State private var reply = ""
    @State private var errorMsg = ""
    @State private var showServerSetting = false
    @AppStorage("serverURL") private var serverURL = "http://6.6.6.130:8901"

    enum Stage {
        case idle, recording, recognizing, chatting
    }

    var body: some View {
        Group {
            VStack(spacing: 24) {
                // 状态圆环按钮：按住说话 / 松手识别
                ZStack {
                    Circle()
                        .fill(stage == .recording ? Color.red.opacity(0.85) : Color.blue.opacity(0.85))
                        .frame(width: 170, height: 170)
                        .shadow(radius: stage == .recording ? 18 : 8)
                    if stage == .recording {
                        Text(String(format: "%.1f", recorder.elapsed))
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: stage == .recognizing ? "waveform.badge.magnifyingglass" : "mic.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.white)
                    }
                }
                .padding(.top, 30)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if stage == .idle { beginRecord() }
                        }
                        .onEnded { _ in
                            if stage == .recording { finishAndSend() }
                        }
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if stage == .recording {
                            finishAndSend()
                        } else if stage == .idle {
                            beginRecord()
                        }
                    }
                )

                Text(status)
                    .font(.headline)
                    .foregroundColor(.secondary)

                // 转写文字
                if !transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("我", systemImage: "person.fill").font(.subheadline).foregroundColor(.blue)
                        Text(transcript)
                            .font(.body)
                            .padding(10)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(10)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 回复
                if !reply.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("小龙虾", systemImage: "ladybug.fill").font(.subheadline).foregroundColor(.orange)
                        Text(reply)
                            .font(.body)
                            .padding(10)
                            .background(Color.orange.opacity(0.08))
                            .cornerRadius(10)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !errorMsg.isEmpty {
                    Text(errorMsg)
                        .font(.footnote)
                        .foregroundColor(.red)
                }

                Spacer()

                Button {
                    showServerSetting = true
                } label: {
                    Label("服务地址", systemImage: "gearshape")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .navigationTitle("超级按键")
            .sheet(isPresented: $showServerSetting) {
                ServerSettingView(serverURL: $serverURL)
            }
        }
    }

    private func beginRecord() {
        guard stage == .idle else { return }
        errorMsg = ""
        transcript = ""
        reply = ""
        recorder.start()
        stage = .recording
        status = "说话中…松手结束"
    }

    private func finishAndSend() {
        guard let url = recorder.stop() else {
            if stage == .recording { stage = .idle; status = "按住说话" }
            return
        }
        stage = .recognizing
        status = "识别中…"
        Task {
            do {
                let text = try await ServerAPI.shared.transcribe(audioURL: url)
                await MainActor.run {
                    transcript = text
                    stage = .chatting
                    status = "对话中…"
                }
                let r = try await ServerAPI.shared.chat(text: text)
                await MainActor.run {
                    reply = r
                    stage = .idle
                    status = "按住说话"
                }
            } catch {
                await MainActor.run {
                    errorMsg = "出错了：\(error.localizedDescription)"
                    stage = .idle
                    status = "按住说话"
                }
            }
        }
    }
}

struct ServerSettingView: View {
    @Binding var serverURL: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("中转服务地址（含端口）")) {
                    TextField("http://6.6.6.130:8901", text: $serverURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .navigationTitle("服务设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { dismiss() }
                }
            }
        }
    }
}