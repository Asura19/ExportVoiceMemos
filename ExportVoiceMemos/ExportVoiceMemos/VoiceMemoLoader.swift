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
            
            // 遍历所有表，查找可能包含语音备忘录的表
            for tableName in tables {
                if tableName.uppercased().contains("RECORDING") || 
                   tableName.uppercased().contains("MEMO") {
                    
                    // 获取表的列信息
                    let columns = try db.columns(in: tableName)
                    print("表 \(tableName) 的列: \(columns.map { $0.name })")
                    
                    // 构建通用查询
                    var titleColumn: String?
                    var pathColumn: String?
                    
                    // 查找可能的标题和路径列
                    for column in columns {
                        let columnName = column.name.uppercased()
                        if columnName.contains("TITLE") || columnName.contains("NAME") {
                            titleColumn = column.name
                        } else if columnName.contains("PATH") || columnName.contains("FILE") {
                            pathColumn = column.name
                        }
                    }
                    
                    // 如果找到了可能的标题和路径列
                    if let titleCol = titleColumn, let pathCol = pathColumn {
                        let rows = try Row.fetchAll(db, sql: "SELECT * FROM \(tableName)")
                        
                        var memos: [VoiceMemo] = []
                        for row in rows {
                            let title = row[titleCol] as? String ?? "未命名备忘录"
                            if let path = row[pathCol] as? String {
                                memos.append(VoiceMemo(
                                    title: title, 
                                    originalPath: path, 
                                    date: Date()
                                ))
                            }
                        }
                        
                        if !memos.isEmpty {
                            return memos
                        }
                    }
                }
            }
            
            // 如果无法找到适当的表结构，尝试更通用的方法
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
}

extension String {
    func appendingPathComponent(_ path: String) -> String {
        return (self as NSString).appendingPathComponent(path)
    }
} 
