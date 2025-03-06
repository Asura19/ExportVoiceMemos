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
    @State private var selectedMemos = Set<UUID>()
    @State private var isExporting = false
    
    var body: some View {
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
                VStack {
                    List(selection: $selectedMemos) {
                        ForEach(voiceMemos) { memo in
                            HStack {
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
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .tag(memo.id)
                        }
                    }
                    .listStyle(.inset)
                }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button(action: {
                            isExporting = true
                            // 这里将来添加导出逻辑
                            print("准备导出 \(selectedMemos.count) 个文件")
                        }) {
                            Label("导出选中项", systemImage: "square.and.arrow.up")
                        }
                        .disabled(selectedMemos.isEmpty)
                        .keyboardShortcut("e", modifiers: [.command])
                    }
                    
                    ToolbarItem(placement: .automatic) {
                        Button(
                            action: {
                                if selectedMemos.count == voiceMemos.count {
                                    selectedMemos.removeAll()
                                } else {
                                    selectedMemos = Set(voiceMemos.map { $0.id })
                                }
                            },
                            label:  {
                                Text(selectedMemos.count == voiceMemos.count ? "取消全选" : "全选")
                            }
                        )
                        .keyboardShortcut("a", modifiers: [.command])
                    }
                }
            }
        }
        .navigationTitle("语音备忘录")
        .frame(minWidth: 600, minHeight: 400)
        .task {
            await loadVoiceMemos()
        }
        .onCommand(#selector(NSResponder.selectAll(_:))) {
            selectedMemos = Set(voiceMemos.map { $0.id })
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
