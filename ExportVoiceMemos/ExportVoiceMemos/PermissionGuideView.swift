//
//  PermissionGuideView.swift
//  ExportVoiceMemos
//

import SwiftUI

struct PermissionGuideView: View {
    var onRetryAccess: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundColor(.orange)
                .padding(.bottom, 10)
            
            Text("需要完全磁盘访问权限")
                .font(.title)
                .fontWeight(.bold)
            
            Text("此应用需要访问语音备忘录数据库才能导出您的录音。")
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("请按照以下步骤授予权限：")
                    .fontWeight(.medium)
                
                HStack(alignment: .top) {
                    Text("1.")
                    Text(#"点击下方按钮前往"系统设置""#)
                }
                
                HStack(alignment: .top) {
                    Text("2.")
                    Text(#"选择"隐私与安全性" > "完全磁盘访问权限""#)
                }
                
                HStack(alignment: .top) {
                    Text("3.")
                    Text("点击锁图标并输入您的密码")
                }
                
                HStack(alignment: .top) {
                    Text("4.")
                    Text(#"找到并勾选"ExportVoiceMemos"应用"#)
                }
                
                HStack(alignment: .top) {
                    Text("5.")
                    Text(#"返回此应用并点击"检查权限"按钮"#)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 10)
            
            Spacer()
            
            HStack(spacing: 15) {
                Button("前往系统设置") {
                    openPrivacySettings()
                }
                .buttonStyle(.borderedProminent)
                
                Button("检查权限") {
                    onRetryAccess()
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 30)
        }
        .frame(width: 500, height: 500)
        .padding()
    }
    
    private func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
} 
