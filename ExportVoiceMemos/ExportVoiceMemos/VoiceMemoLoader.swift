//
//  VoiceMemoLoader.swift
//  ExportVoiceMemos
//
//  Created by phoenix on 2025/3/4.
//

import Foundation
import GRDB
import SwiftUI
import AppKit

enum VoiceMemoLoaderError: Error {
    case fileNotFound
    case databaseError(String)
    case invalidData
    case accessDenied
}

class VoiceMemoLoader {
    static func loadVoiceMemos() async throws -> [VoiceMemo] {
        return try await Task {
 
            // 如果iCloud容器不可用，尝试直接访问本地目录
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            
            // 新版本位置
            let newPath = homeDir.appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings")
            // 先尝试新路径
            if let dbPath = findDatabaseIn(newPath) {
                return try readVoiceMemosFromDatabase(dbPath)
            }
            else {
                throw VoiceMemoLoaderError.fileNotFound
            }
        }.value
    }
    
    private static func findDatabaseIn(_ directory: URL) -> URL? {
        // 尝试找到数据库文件
        let possibleDBNames = ["CloudRecordings.db", "Recordings.db", "CloudRecording.db"]
        
        for dbName in possibleDBNames {
            let dbPath = directory.appendingPathComponent(dbName)
            if FileManager.default.fileExists(atPath: dbPath.path) {
                return dbPath
            }
        }
        
        return nil
    }
    
    private static func readVoiceMemosFromDatabase(_ dbURL: URL) throws -> [VoiceMemo] {
        do {
            // 打开数据库连接
            let dbQueue = try DatabaseQueue(path: dbURL.path)
            return try readDatabase(dbQueue)
        } catch {
            throw VoiceMemoLoaderError.databaseError("数据库操作失败: \(error.localizedDescription)")
        }
    }
    
    
    
    private static func readDatabase(_ dbQueue: DatabaseQueue) throws -> [VoiceMemo] {
        return try dbQueue.read { db in
            // 获取所有表名
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master 
                WHERE type='table'
                """)
            
            print("数据库中的表: \(tables)")
            
            // 首先尝试直接使用ZCLOUDRECORDING表
            if tables.contains("ZCLOUDRECORDING") {
                // 获取表的列信息以确认结构
                let columns = try db.columns(in: "ZCLOUDRECORDING")
                let columnNames = columns.map { $0.name }
                print("ZCLOUDRECORDING表的列: \(columnNames)")
                
                // 检查是否包含我们需要的列
                if columnNames.contains("ZCUSTOMLABEL") && 
                   columnNames.contains("ZENCRYPTEDTITLE") && 
                   columnNames.contains("ZPATH") {
                    
                    // 使用SQL查询直接获取数据，根据ZCUSTOMLABEL时间戳倒序排列
                    let rows = try Row.fetchAll(db, sql: """
                        SELECT ZENCRYPTEDTITLE, ZPATH, ZCUSTOMLABEL, ZCUSTOMLABELFORSORTING 
                        FROM ZCLOUDRECORDING 
                        ORDER BY ZCUSTOMLABEL DESC
                        """)
                    
                    print("查询到\(rows.count)条记录")
                    
                    var memos: [VoiceMemo] = []
                    for row in rows {
                        // 标题优先使用ZCUSTOMLABELFORSORTING，如果不存在则使用ZENCRYPTEDTITLE
                        let title: String
                        if let sortingTitle = row["ZCUSTOMLABELFORSORTING"] as? String, !sortingTitle.isEmpty {
                            title = sortingTitle
                        } else {
                            title = row["ZENCRYPTEDTITLE"] as? String ?? "未命名备忘录"
                        }
                        
                        // 从ZPATH获取文件路径
                        guard let relativePath = row["ZPATH"] as? String else {
                            continue
                        }
                        
                        // 构建完整路径
                        let homeDir = FileManager.default.homeDirectoryForCurrentUser
                        let baseDir = homeDir.appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings")
                        let fullPath = baseDir.appendingPathComponent(relativePath).path
                        
                        // 从ZCUSTOMLABEL获取日期
                        let date: Date
                        if let dateString = row["ZCUSTOMLABEL"] as? String, !dateString.isEmpty {
                            date = parseDate(dateString) ?? Date()
                        } else {
                            date = Date()
                        }
                        
                        memos.append(VoiceMemo(
                            title: title,
                            originalPath: fullPath,
                            date: date
                        ))
                    }
                    
                    if !memos.isEmpty {
                        return memos
                    }
                }
            }
            
            // 如果特定表访问失败，回退到通用逻辑
            // 检查所有表的所有列
            for tableName in tables {
                let rows = try Row.fetchAll(db, sql: "SELECT * FROM \(tableName) LIMIT 10")
                
                if !rows.isEmpty {
                    print("表 \(tableName) 的示例数据: \(rows[0])")
                }
            }
            
            throw VoiceMemoLoaderError.invalidData
        }
    }
    
    // 解析ISO 8601日期字符串
    private static func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
}

extension String {
    func appendingPathComponent(_ path: String) -> String {
        return (self as NSString).appendingPathComponent(path)
    }
} 
