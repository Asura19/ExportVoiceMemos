//
//  ContentView.swift
//  ExportVoiceMemos
//
//  Created by phoenix on 2025/3/4.
//

import SwiftUI
import UniformTypeIdentifiers

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
    @State private var exportingProgress: Double = 0
    @State private var showExportSuccess = false
    
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
                            exportSelectedMemos()
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
        .alert("导出成功", isPresented: $showExportSuccess) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("已成功导出选中的语音备忘录")
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
    
    private func exportSelectedMemos() {
        // 获取选中的语音备忘录
        let memosToExport = voiceMemos.filter { selectedMemos.contains($0.id) }
        guard !memosToExport.isEmpty else { return }
        
        // 创建保存面板
        let savePanel = NSOpenPanel()
        savePanel.canChooseFiles = false
        savePanel.canChooseDirectories = true
        savePanel.allowsMultipleSelection = false
        savePanel.message = "请选择保存语音备忘录的文件夹"
        savePanel.prompt = "选择文件夹"
        
        // 在主线程上显示保存面板
        Task { @MainActor in
            let response = savePanel.runModal()
            if response == .OK, let targetDirectory = savePanel.url {
                Task {
                    await exportFiles(memosToExport, to: targetDirectory)
                }
            }
        }
    }
    
    private func exportFiles(_ memos: [VoiceMemo], to directory: URL) async {
        isExporting = true
        exportingProgress = 0
        
        do {
            let fileManager = FileManager.default
            var successCount = 0
            
            for (index, memo) in memos.enumerated() {
                // 从路径中提取文件名
                let fileName = memo.originalPath.components(separatedBy: "/").last ?? "未命名录音.m4a"
                
                // 构建源文件路径 - 确保使用完整路径
                let sourceURL = URL(fileURLWithPath: memo.originalPath)
                let destinationURL = directory.appendingPathComponent("\(memo.title)")
                
                print("尝试复制文件：\(sourceURL.path) 到 \(destinationURL.path)")
                
                // 检查文件是否存在
                if fileManager.fileExists(atPath: sourceURL.path) {
                    do {
                        // 复制文件
                        try fileManager.copyItem(at: sourceURL, to: destinationURL)
                        successCount += 1
                        print("成功复制文件：\(fileName)")
                    } catch {
                        print("导出文件失败: \(error.localizedDescription)")
                    }
                } else {
                    print("源文件不存在: \(sourceURL.path)")
                    // 尝试不同的方式构建路径
                    let alternativePath = "/Users/\(NSUserName())/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings/\(fileName)"
                    let alternativeURL = URL(fileURLWithPath: alternativePath)
                    
                    if fileManager.fileExists(atPath: alternativePath) {
                        do {
                            try fileManager.copyItem(at: alternativeURL, to: destinationURL)
                            successCount += 1
                            print("使用备选路径成功复制文件：\(fileName)")
                        } catch {
                            print("使用备选路径导出失败: \(error.localizedDescription)")
                        }
                    } else {
                        print("备选路径也不存在: \(alternativePath)")
                    }
                }
                
                // 更新进度
                exportingProgress = Double(index + 1) / Double(memos.count)
            }
            
            // 更新UI
            await MainActor.run {
                isExporting = false
                showExportSuccess = successCount > 0
            }
            
        } catch {
            await MainActor.run {
                isExporting = false
                errorMessage = "导出过程中出错: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    ContentView()
}
