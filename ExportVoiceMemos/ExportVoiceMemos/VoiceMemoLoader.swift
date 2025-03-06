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
            // 尝试查找新位置
            let containerURL = try FileManager.default.url(
                forUbiquityContainerIdentifier: nil)?
                .appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings")
            
            // 如果iCloud容器不可用，尝试直接访问本地目录
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            
            // 新版本位置
            let newPath = homeDir.appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings")
            // 旧版本位置
            let oldPath = homeDir.appendingPathComponent("Library/Application Support/com.apple.voicememos/Recordings")
            
            // 请求访问这些目录
//            if !requestAccess(to: newPath) {
//                throw VoiceMemoLoaderError.accessDenied
//            }
            
            // 先尝试新路径
            if let dbPath = findDatabaseIn(newPath) {
                return try readVoiceMemosFromDatabase(dbPath)
            } 
            // 再尝试旧路径
            else if let dbPath = findDatabaseIn(oldPath) {
                return try readVoiceMemosFromDatabase(dbPath)
            }
            // 最后尝试iCloud容器
            else if let containerURL = containerURL, let dbPath = findDatabaseIn(containerURL) {
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
            
            // 尝试所有可能的数据库表结构
            do {
                return try readNewFormatDatabase(dbQueue)
            } catch {
                do {
                    return try readOldFormatDatabase(dbQueue)
                } catch {
                    return try readAlternativeFormatDatabase(dbQueue)
                }
            }
        } catch {
            throw VoiceMemoLoaderError.databaseError("数据库操作失败: \(error.localizedDescription)")
        }
    }
    
    private static func readNewFormatDatabase(_ dbQueue: DatabaseQueue) throws -> [VoiceMemo] {
        let memos = try dbQueue.read { db in
            // 先检查表是否存在
            if try db.tableExists("ZCLOUDRECORDING") {
                // 使用SQL查询直接获取数据
                let rows = try Row.fetchAll(db, sql: """
                    SELECT ZENCRYPTEDTITLE, ZPATH, ZTIMESTAMP 
                    FROM ZCLOUDRECORDING 
                    ORDER BY ZLOCALDURATION DESC
                    """)
                
                // 打印表结构信息
                let columns = try db.columns(in: "ZCLOUDRECORDING")
                for column in columns {
                    print("Column: \(column.name) Type: \(column.type)")
                }
                
                var result: [VoiceMemo] = []
                for row in rows {
                    // 获取标题
                    let title = row["ZENCRYPTEDTITLE"] as? String ?? "未命名备忘录"
                    
                    // 获取路径
                    if let path = row["ZPATH"] as? String {
                        // 获取日期，如果可用
                        let timestamp: Date
                        if let date = row["ZTIMESTAMP"] as? Date {
                            timestamp = date
                        } else {
                            timestamp = Date()
                        }
                        
                        result.append(VoiceMemo(
                            title: title,
                            originalPath: path,
                            date: timestamp
                        ))
                    }
                }
                
                return result
            } else {
                throw VoiceMemoLoaderError.invalidData
            }
        }
        
        guard !memos.isEmpty else {
            throw VoiceMemoLoaderError.invalidData
        }
        
        return memos
    }
    
    private static func readOldFormatDatabase(_ dbQueue: DatabaseQueue) throws -> [VoiceMemo] {
        let memos = try dbQueue.read { db in
            // 检查旧格式表
            if try db.tableExists("RECORDING") {
                let rows = try Row.fetchAll(db, sql: """
                    SELECT TITLE, PATH, TIMESTAMP 
                    FROM RECORDING
                    """)
                
                var result: [VoiceMemo] = []
                for row in rows {
                    let title = row["TITLE"] as? String ?? "未命名备忘录"
                    
                    if let path = row["PATH"] as? String {
                        let timestamp = row["TIMESTAMP"] as? Date ?? Date()
                        
                        result.append(VoiceMemo(
                            title: title,
                            originalPath: path,
                            date: timestamp
                        ))
                    }
                }
                
                return result
            } else {
                throw VoiceMemoLoaderError.invalidData
            }
        }
        
        guard !memos.isEmpty else {
            throw VoiceMemoLoaderError.invalidData
        }
        
        return memos
    }
    
    private static func readAlternativeFormatDatabase(_ dbQueue: DatabaseQueue) throws -> [VoiceMemo] {
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
