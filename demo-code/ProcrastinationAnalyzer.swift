//
//  ProcrastinationAnalyzer.swift
//  FocusMate
//
//  Created by FocusMate on Date.
//

import Foundation
import SwiftUI

// MARK: - Procrastination Level Enum
enum ProcrastinationLevel: String, CaseIterable {
    case excellent = "Excellent"
    case average = "Average"
    case needsImprovement = "Needs Improvement"
    
    var color: Color {
        switch self {
        case .excellent:
            return .green
        case .average:
            return .orange
        case .needsImprovement:
            return .red
        }
    }
    
    var description: String {
        switch self {
        case .excellent:
            return "Great focus! Keep this momentum going"
        case .average:
            return "Good pace, stay consistent with deadlines"
        case .needsImprovement:
            return "Focus needed - prioritize urgent tasks first"
        }
    }
}

// MARK: - Additional Structures for Detailed Analysis
struct ProcrastinationAnalysis {
    let score: Int
    let level: ProcrastinationLevel
    let factors: [ProcrastinationFactor]
    let summary: String
    let recommendations: [String]
    
    init(score: Int, level: ProcrastinationLevel, factors: [ProcrastinationFactor] = [], summary: String = "", recommendations: [String] = []) {
        self.score = score
        self.level = level
        self.factors = factors
        self.summary = summary
        self.recommendations = recommendations
    }
}

struct ProcrastinationFactor {
    let title: String
    let description: String
    let impact: Double // 0.0 to 1.0
    let suggestion: String
    
    init(title: String, description: String, impact: Double, suggestion: String) {
        self.title = title
        self.description = description
        self.impact = max(0.0, min(1.0, impact))
        self.suggestion = suggestion
    }
}

// MARK: - Procrastination Analysis Data
struct ProcrastinationAnalysisData {
    let score: Int
    let level: ProcrastinationLevel
    let completedTasks: Int
    let totalTasks: Int
    let overdueTasks: Int
    let trends: [Int] // Weekly trends
    
    init(score: Int = 0, completedTasks: Int = 0, totalTasks: Int = 0, overdueTasks: Int = 0, trends: [Int] = []) {
        self.score = score
        self.completedTasks = completedTasks
        self.totalTasks = totalTasks
        self.overdueTasks = overdueTasks
        self.trends = trends
        
        // Determine level based on score
        switch score {
        case 0...40:
            self.level = .excellent
        case 41...70:
            self.level = .average
        default:
            self.level = .needsImprovement
        }
    }
}

// MARK: - Procrastination Analyzer
class ProcrastinationAnalyzer: ObservableObject {
    @Published var analysisData = ProcrastinationAnalysisData()
    
    func calculateProcrastinationScore(from tasks: [TaskItem]) -> Int {
        guard !tasks.isEmpty else { return 0 }
        
        let now = Date()
        let calendar = Calendar.current
        
        var score = 0
        var factorCount = 0
        
        // Factor 1: Completion rate (40% weight)
        let completedTasks = tasks.filter { $0.isCompleted }
        let completionRate = Double(completedTasks.count) / Double(tasks.count)
        score += Int((1.0 - completionRate) * 40)
        factorCount += 40
        
        // Factor 2: Overdue tasks (30% weight)
        let overdueTasks = tasks.filter { task in
            !task.isCompleted && task.dueDate != nil && task.dueDate! < now
        }
        let overdueRate = tasks.isEmpty ? 0.0 : Double(overdueTasks.count) / Double(tasks.count)
        score += Int(overdueRate * 30)
        factorCount += 30
        
        // Factor 3: Task creation vs completion pattern (20% weight)
        let recentTasks = tasks.filter { task in
            calendar.isDate(task.createdDate, inSameDayAs: now)
        }
        let recentCompletedTasks = recentTasks.filter { $0.isCompleted }
        
        if !recentTasks.isEmpty {
            let recentCompletionRate = Double(recentCompletedTasks.count) / Double(recentTasks.count)
            score += Int((1.0 - recentCompletionRate) * 20)
        } else {
            score += 10 // Moderate penalty for no recent activity
        }
        factorCount += 20
        
        // Factor 4: Time management (10% weight)
        let urgentTasks = tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            let timeUntilDue = dueDate.timeIntervalSince(now)
            return timeUntilDue <= 24 * 60 * 60 && timeUntilDue > 0 // Due within 24 hours
        }
        let urgentCompletedTasks = urgentTasks.filter { $0.isCompleted }
        
        if !urgentTasks.isEmpty {
            let urgentCompletionRate = Double(urgentCompletedTasks.count) / Double(urgentTasks.count)
            score += Int((1.0 - urgentCompletionRate) * 10)
        }
        factorCount += 10
        
        // Ensure score is within 0-100 range
        return min(100, max(0, score))
    }
    
    func updateAnalysis(with tasks: [TaskItem]) {
        let score = calculateProcrastinationScore(from: tasks)
        let completedTasks = tasks.filter { $0.isCompleted }.count
        let overdueTasks = tasks.filter { task in
            !task.isCompleted && task.dueDate != nil && task.dueDate! < Date()
        }.count
        
        analysisData = ProcrastinationAnalysisData(
            score: score,
            completedTasks: completedTasks,
            totalTasks: tasks.count,
            overdueTasks: overdueTasks
        )
    }
    
    func getStatusMessage() -> String {
        return analysisData.level.description
    }
    
    func getScoreColor() -> Color {
        return analysisData.level.color
    }
}