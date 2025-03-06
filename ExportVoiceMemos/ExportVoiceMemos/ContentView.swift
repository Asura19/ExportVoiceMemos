//
//  ContentView.swift
//  ExportVoiceMemos
//
//  Created by phoenix on 2025/3/4.
//

import SwiftUI

struct VoiceMemo: Identifiable {
    let id = UUID()
    let title: String
    let originalPath: String
    let date: Date
}

struct ContentView: View {
    @State private var voiceMemos: [VoiceMemo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("加载中...")
                } else if let error = errorMessage {
                    VStack {
                        Text("错误：\(error)")
                            .foregroundColor(.red)
                        Button("重试") {
                            Task {
                                await loadVoiceMemos()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if voiceMemos.isEmpty {
                    Text("未找到语音备忘录")
                } else {
                    List(voiceMemos) { memo in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(memo.title)
                                .font(.headline)
                            Text(memo.originalPath.components(separatedBy: "/").last ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formatDate(memo.date))
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("语音备忘录")
            .task {
                await loadVoiceMemos()
            }
        }
    }
    
    private func loadVoiceMemos() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let memos = try await VoiceMemoLoader.loadVoiceMemos()
            self.voiceMemos = memos
            self.isLoading = false
        } catch VoiceMemoLoaderError.accessDenied {
            self.errorMessage = "访问被拒绝或取消选择，请选择正确的数据库文件"
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView()
}
