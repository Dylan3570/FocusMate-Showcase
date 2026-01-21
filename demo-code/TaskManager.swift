//
//  TaskManager.swift
//  FocusMate
//
//  Created by Guanheng Wang on 08/08/2025.
//

import Foundation
import SwiftUI
import UserNotifications

// MARK: - Badge Manager
class BadgeManager: ObservableObject {
    static let shared = BadgeManager()
    
    @Published var currentBadgeCount: Int = 0
    
    private init() {
        loadBadgeCount()
    }
    
    func incrementBadge() {
        currentBadgeCount += 1
        updateSystemBadge()
        saveBadgeCount()
    }
    
    func decrementBadge() {
        currentBadgeCount = max(0, currentBadgeCount - 1)
        updateSystemBadge()
        saveBadgeCount()
    }
    
    func clearBadge() {
        currentBadgeCount = 0
        updateSystemBadge()
        saveBadgeCount()
    }
    
    private func updateSystemBadge() {
        #if os(iOS)
        UNUserNotificationCenter.current().setBadgeCount(currentBadgeCount) { error in
            if let error = error {
                print("Failed to update badge: \(error.localizedDescription)")
            } else {
                print("Badge updated: \(self.currentBadgeCount)")
            }
        }
        #endif
    }
    
    private func saveBadgeCount() {
        UserDefaults.standard.set(currentBadgeCount, forKey: "app_badge_count")
    }
    
    private func loadBadgeCount() {
        currentBadgeCount = UserDefaults.standard.integer(forKey: "app_badge_count")
    }
}

// MARK: - Task Data Models
struct TaskItem: Identifiable, Codable, Equatable {
    let id = UUID()
    var title: String
    var description: String
    var priority: TaskPriority
    var status: TaskStatus
    var dueDate: Date?
    var isCompleted: Bool
    var completedDate: Date?
    var category: TaskCategory
    var createdDate: Date
    
    init(title: String, description: String = "", priority: TaskPriority = .medium, status: TaskStatus = .pending, dueDate: Date? = nil, category: TaskCategory = .general) {
        self.title = title
        self.description = description
        self.priority = priority
        self.status = status
        self.dueDate = dueDate
        self.isCompleted = false
        self.completedDate = nil
        self.category = category
        self.createdDate = Date()
    }
}

enum TaskPriority: String, CaseIterable, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    
    var color: Color {
        switch self {
        case .low:
            return HarmoniousColors.warmGreen
        case .medium:
            return HarmoniousColors.primaryOrange
        case .high:
            return HarmoniousColors.warmRed
        }
    }
    
    var icon: String {
        switch self {
        case .low:
            return "arrow.down.circle"
        case .medium:
            return "minus.circle"
        case .high:
            return "exclamationmark.circle"
        }
    }
}

enum TaskStatus: String, CaseIterable, Codable {
    case pending = "Pending"
    case inProgress = "In Progress"
    case completed = "Completed"
    case overdue = "Overdue"
    
    var color: Color {
        switch self {
        case .pending:
            return .orange
        case .inProgress:
            return .blue
        case .completed:
            return .green
        case .overdue:
            return .red
        }
    }
}

enum TaskCategory: String, CaseIterable, Codable {
    case study = "Study"
    case work = "Work"
    case personal = "Personal"
    case health = "Health"
    case general = "General"
    
    var icon: String {
        switch self {
        case .study:
            return "book"
        case .work:
            return "briefcase"
        case .personal:
            return "person"
        case .health:
            return "heart"
        case .general:
            return "folder"
        }
    }
}

// MARK: - Task Manager
class TaskManager: ObservableObject {
    @Published var tasks: [TaskItem] {
        didSet {
            saveTasks()
            // Automatically update procrastination analysis when tasks are updated
            updateProcrastinationAnalysis()
        }
    }
    @Published var streakManager: StreakManager
    @Published var growthManager: GrowthManager
    @Published var achievementManager: AchievementManager
    @Published var procrastinationAnalyzer = ProcrastinationAnalyzer()
    @Published var pomodoroManager: PomodoroManager
    let badgeManager: BadgeManager
    
    // Method to force UI updates when growth data changes
    func notifyGrowthDataChanged() {
        objectWillChange.send()
    }
    
    private let userDefaultsKey = "SavedTasks"
    private let editModeKey = "EditModeState"
    private let calendar = Calendar.current
    private var currentUserId: String?
    
    init(userId: String? = nil) {
        self.currentUserId = userId
        self.streakManager = StreakManager(userId: userId)
        self.growthManager = GrowthManager(userId: userId)
        self.achievementManager = AchievementManager(userId: userId)
        self.pomodoroManager = PomodoroManager(userId: userId)
        self.badgeManager = BadgeManager.shared
        _tasks = Published(initialValue: [])
        
        // Connect AchievementManager to TaskManager for real-time updates
        achievementManager.setTaskManager(self)
        
        // Only load data when user ID is available
        if let userId = userId {
            // Check if this is the first launch for this user
            let firstLaunchKey = getUserSpecificKey("HasLaunchedBefore")
            let isFirstLaunch = !UserDefaults.standard.bool(forKey: firstLaunchKey)
            
            if isFirstLaunch {
                // First launch for this user - start fresh
                UserDefaults.standard.set(true, forKey: firstLaunchKey)
                UserDefaults.standard.set(Date(), forKey: getUserSpecificKey("FirstLaunchDate"))
                tasks = []
                print("DEBUG: TaskManager - First launch for user \(userId), starting with empty tasks")
            } else {
                // Not first launch for this user - load saved tasks
                loadTasks()
            }
        } else {
            print("DEBUG: TaskManager - Initialized without user ID, tasks will be loaded when user is set")
        }
        
        // Connect StreakManager to GrowthManager
        streakManager.growthManager = growthManager
        
        // Listen for growth data changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(growthDataChanged),
            name: .growthDataChanged,
            object: nil
        )
        
        // Perform initial procrastination analysis after initialization with longer delay to avoid blocking UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.updateProcrastinationAnalysis()
        }
    }
    
    // MARK: - User Management
    
    func setCurrentUser(_ userId: String) {
        // If there was a previous user, save their data first
        if let previousUserId = self.currentUserId, previousUserId != userId {
            print("DEBUG: TaskManager - Switching from user \(previousUserId) to \(userId), saving previous user data")
            saveTasks()
            
            // Clear current tasks before switching to new user
            tasks = []
        }
        
        self.currentUserId = userId
        
        // Update all managers with new user ID
        streakManager.setCurrentUser(userId)
        growthManager.setCurrentUser(userId)
        achievementManager.setCurrentUser(userId)
        pomodoroManager.setCurrentUser(userId)
        
        // Reconnect managers
        streakManager.growthManager = growthManager
        achievementManager.setTaskManager(self)
        
        // Load tasks for this user
        loadTasks()
        print("DEBUG: TaskManager - Loaded tasks for user \(userId): \(tasks.count) tasks")
    }
    
    func clearCurrentUser() {
        // Save current user data before clearing user
        if let userId = self.currentUserId {
            print("DEBUG: TaskManager - Clearing user \(userId), saving data before clear")
            saveTasks()
        }
        
        // Clear all user-specific data
        self.currentUserId = nil
        self.tasks = []
        
        // Clear all managers' user data
        streakManager.clearCurrentUser()
        growthManager.clearCurrentUser()
        achievementManager.clearCurrentUser()
        pomodoroManager.clearCurrentUser()
    }
    
    @objc private func growthDataChanged() {
        DispatchQueue.main.async {
            self.notifyGrowthDataChanged()
        }
    }
    
    // MARK: - Task Management
    
    func addTask(_ task: TaskItem) {
        tasks.append(task)
        saveTasks()
    }
    
    func toggleTaskCompletion(_ task: TaskItem) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            let wasCompleted = tasks[index].isCompleted
            tasks[index].isCompleted.toggle()
            
            if tasks[index].isCompleted && !wasCompleted {
                // Task was just completed
                tasks[index].completedDate = Date()
                streakManager.taskCompleted() // Auto-update streak
                
                // Award points for task completion
                growthManager.awardPointsForTaskCompletion(priority: task.priority)
                
                // Update completed tasks count
                let completedCount = tasks.filter { $0.isCompleted }.count
                growthManager.updateCompletedTasksCount(completedCount)
                
                // Update achievement progress and check for unlocks
                achievementManager.updateProgress()
                
                // Decrement badge for this specific task when it's completed (only if badge count > 0)
                if badgeManager.currentBadgeCount > 0 {
                    badgeManager.decrementBadge()
                    print("Badge decremented for specific task \(task.id.uuidString) after completion. Current count: \(badgeManager.currentBadgeCount)")
                } else {
                    print("No badge to decrement for task \(task.id.uuidString) completion")
                }
            } else if !tasks[index].isCompleted && wasCompleted {
                // Task was uncompleted
                tasks[index].completedDate = nil
                
                // Deduct points for uncompleting task
                growthManager.deductPointsForTaskUncompletion(priority: task.priority)
                
                // Update completed tasks count
                let completedCount = tasks.filter { $0.isCompleted }.count
                growthManager.updateCompletedTasksCount(completedCount)
                
                // Update achievement progress after uncompleting
                achievementManager.updateProgress()
                
                // Handle streak when task is uncompleted
                streakManager.taskUncompleted()
            }
            
            saveTasks()
            
            // Send points change notification
            NotificationCenter.default.post(name: .pointsChanged, object: nil)
        }
    }
    
    func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
    }
    
    // MARK: - Data Persistence
    
    private func saveTasks() {
        let key = getUserSpecificKey(userDefaultsKey)
        if let encoded = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(encoded, forKey: key)
            print("DEBUG: TaskManager - Saved \(tasks.count) tasks for user \(currentUserId ?? "unknown") with key: \(key)")
        } else {
            print("ERROR: TaskManager - Failed to encode tasks for user \(currentUserId ?? "unknown")")
        }
    }
    
    private func loadTasks() {
        let key = getUserSpecificKey(userDefaultsKey)
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) {
            tasks = decoded
            print("DEBUG: TaskManager - Loaded \(tasks.count) tasks for user \(currentUserId ?? "unknown") from key: \(key)")
        } else {
            tasks = []
            print("DEBUG: TaskManager - No saved tasks found for user \(currentUserId ?? "unknown") with key: \(key), starting with empty task list")
        }
    }
    
    // MARK: - Edit Mode Persistence
    
    func saveEditModeState(_ isEditMode: Bool) {
        let key = getUserSpecificKey(editModeKey)
        UserDefaults.standard.set(isEditMode, forKey: key)
    }
    
    func loadEditModeState() -> Bool {
        let key = getUserSpecificKey(editModeKey)
        return UserDefaults.standard.bool(forKey: key)
    }
    
    // MARK: - Helper Methods
    
    private func getUserSpecificKey(_ baseKey: String) -> String {
        guard let userId = currentUserId else {
            print("ERROR: TaskManager - No current user ID, cannot generate user-specific key for: \(baseKey)")
            // Return a temporary key that won't conflict with user data
            return "\(baseKey)_temp_\(UUID().uuidString)"
        }
        
        let key = "\(baseKey)_\(userId)"
        print("DEBUG: TaskManager - Generated user-specific key: \(key) for user: \(userId)")
        return key
    }
    
    // MARK: - Task Filtering and Queries
    
    func getFilteredTasks(searchText: String = "", priority: String = "All Priority", status: String = "All Status") -> [TaskItem] {
        var filteredTasks = tasks
        
        // Filter by search text
        if !searchText.isEmpty {
            filteredTasks = filteredTasks.filter { task in
                task.title.localizedCaseInsensitiveContains(searchText) ||
                task.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Filter by priority
        if priority != "All Priority" {
            filteredTasks = filteredTasks.filter { task in
                task.priority.rawValue == priority
            }
        }
        
        // Filter by status
        if status != "All Status" {
            filteredTasks = filteredTasks.filter { task in
                task.status.rawValue == status
            }
        }
        
        return filteredTasks
    }
    
    func getCompletedTasksCount() -> Int {
        return tasks.filter { $0.isCompleted }.count
    }
    
    func getTotalTasksCount() -> Int {
        return tasks.count
    }
    
    // MARK: - Today's Tasks Statistics
    
    /// Get tasks created today (for Today's Overview)
    func getTodayCreatedTasks() -> [TaskItem] {
        let today = Calendar.current.startOfDay(for: Date())
        return tasks.filter { task in
            Calendar.current.isDate(task.createdDate, inSameDayAs: today)
        }
    }
    
    /// Get tasks completed today
    func getTodayCompletedTasks() -> [TaskItem] {
        let today = Calendar.current.startOfDay(for: Date())
        return tasks.filter { task in
            guard let completedDate = task.completedDate else { return false }
            return Calendar.current.isDate(completedDate, inSameDayAs: today)
        }
    }
    
    /// Get count of tasks created today
    func getTodayCreatedTasksCount() -> Int {
        return getTodayCreatedTasks().count
    }
    
    /// Get count of tasks completed today
    func getTodayCompletedTasksCount() -> Int {
        return getTodayCompletedTasks().count
    }
    
    // Removed duration-related methods for simplified task management
    
    func areAllTodayTasksCompleted() -> Bool {
        let todayTasks = getTodayTasks()
        guard !todayTasks.isEmpty else { return false }
        return todayTasks.allSatisfy { $0.isCompleted }
    }
    
    func getTodayTasks() -> [TaskItem] {
        let today = Calendar.current.startOfDay(for: Date())
        return tasks.filter { task in
            if let dueDate = task.dueDate {
                return Calendar.current.isDate(dueDate, inSameDayAs: today)
            }
            return false
        }
    }
    
    func getEarliestTasks(limit: Int = 3) -> [TaskItem] {
        return Array(tasks.prefix(limit))
    }
    
    func getTasksByPriority(_ priority: TaskPriority) -> [TaskItem] {
        return tasks.filter { $0.priority == priority }
    }
    
    func getOverdueTasks() -> [TaskItem] {
        let today = Date()
        return tasks.filter { task in
            if let dueDate = task.dueDate {
                return dueDate < today && !task.isCompleted
            }
            return false
        }
    }
    
    // MARK: - Weekly Performance Data
    
    func getWeeklyProgressData() -> [String: (completed: Int, total: Int)] {
        let calendar = Calendar.current
        let today = Date()
        
        // Get the start of the current week (Monday)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        
        var weeklyData: [String: (completed: Int, total: Int)] = [:]
        
        // Generate data for Monday through Sunday in correct order
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: i, to: weekStart) {
                let dayName = getDayName(from: date)
                let completedTasks = getTasksCompletedOnDate(date)
                let totalTasks = getTasksDueOnDate(date)
                weeklyData[dayName] = (completedTasks.count, totalTasks.count)
            }
        }
        
        return weeklyData
    }
    
    /// Get tasks due on a specific date
    func getTasksDueOnDate(_ date: Date) -> [TaskItem] {
        return tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return Calendar.current.isDate(dueDate, inSameDayAs: date)
        }
    }
    
    /// Get tasks completed on a specific date
    func getTasksCompletedOnDate(_ date: Date) -> [TaskItem] {
        return tasks.filter { task in
            guard let completedDate = task.completedDate else { return false }
            return Calendar.current.isDate(completedDate, inSameDayAs: date)
        }
    }
    
    /// Get day name in short format (Mon, Tue, etc.)
    private func getDayName(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    // MARK: - Procrastination Analysis
    
    /// Update procrastination analysis when tasks change
    private func updateProcrastinationAnalysis() {
        procrastinationAnalyzer.updateAnalysis(with: tasks)
    }
    
    // MARK: - Monthly Statistics
    
    /// Get tasks created in current month
    func getCurrentMonthCreatedTasks() -> [TaskItem] {
        let calendar = Calendar.current
        let today = Date()
        let currentMonth = calendar.component(.month, from: today)
        let currentYear = calendar.component(.year, from: today)
        
        return tasks.filter { task in
            let taskMonth = calendar.component(.month, from: task.createdDate)
            let taskYear = calendar.component(.year, from: task.createdDate)
            return taskMonth == currentMonth && taskYear == currentYear
        }
    }
    
    /// Get tasks completed in current month
    func getCurrentMonthCompletedTasks() -> [TaskItem] {
        let calendar = Calendar.current
        let today = Date()
        let currentMonth = calendar.component(.month, from: today)
        let currentYear = calendar.component(.year, from: today)
        
        return tasks.filter { task in
            guard let completedDate = task.completedDate else { return false }
            let taskMonth = calendar.component(.month, from: completedDate)
            let taskYear = calendar.component(.year, from: completedDate)
            return taskMonth == currentMonth && taskYear == currentYear
        }
    }
    
    /// Get count of tasks created in current month
    func getCurrentMonthCreatedTasksCount() -> Int {
        return getCurrentMonthCreatedTasks().count
    }
    
    /// Get count of tasks completed in current month
    func getCurrentMonthCompletedTasksCount() -> Int {
        return getCurrentMonthCompletedTasks().count
    }
    
    // MARK: - Debug Methods
    
    func debugDataStorage() {
        print("=== TaskManager Debug Info ===")
        print("Current User ID: \(currentUserId ?? "nil")")
        print("Current Tasks Count: \(tasks.count)")
        
        if let userId = currentUserId {
            let key = getUserSpecificKey(userDefaultsKey)
            print("Storage Key: \(key)")
            
            if let data = UserDefaults.standard.data(forKey: key) {
                print("Data exists in UserDefaults with size: \(data.count) bytes")
                if let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) {
                    print("Successfully decoded \(decoded.count) tasks from storage")
                } else {
                    print("Failed to decode tasks from storage")
                }
            } else {
                print("No data found in UserDefaults for key: \(key)")
            }
        }
        
        // Check all UserDefaults keys that might contain task data
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        let taskKeys = allKeys.filter { $0.contains("SavedTasks") }
        print("All task-related keys in UserDefaults: \(taskKeys)")
        print("================================")
    }
    
    // MARK: - Test Methods
    
    func addTestTask() {
        let testTask = TaskItem(
            title: "Test Task \(Date().timeIntervalSince1970)",
            description: "This is a test task to verify data persistence",
            priority: .medium,
            status: .pending,
            category: .general
        )
        addTask(testTask)
        print("DEBUG: Added test task: \(testTask.title)")
    }
    
    // MARK: - Demo Data for Apple Review
    
    func setupDemoDataForReviewer() {
        // Only setup demo data for reviewer account
        guard let userId = currentUserId else { return }
        
        // Check if this is a reviewer account (case-sensitive)
        let isReviewerAccount = userId.contains("Reviewer")
        guard isReviewerAccount else { 
            print("DEBUG: Not a reviewer account, skipping demo data setup")
            return 
        }
        
        // Check if demo data already exists
        let demoKey = getUserSpecificKey("DemoDataSetup")
        if UserDefaults.standard.bool(forKey: demoKey) {
            print("DEBUG: Demo data already setup for reviewer account")
            return
        }
        
        // Clear existing tasks first
        tasks.removeAll()
        
        // Create demo tasks with various priorities and categories
        let demoTasks = [
            TaskItem(
                title: "Review App Store Guidelines",
                description: "Go through the latest App Store review guidelines to ensure compliance",
                priority: .high,
                status: .completed,
                dueDate: Calendar.current.date(byAdding: .day, value: -2, to: Date()),
                category: .work
            ),
            TaskItem(
                title: "Complete SwiftUI Tutorial",
                description: "Learn advanced SwiftUI concepts for better app development",
                priority: .medium,
                status: .inProgress,
                dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
                category: .study
            ),
            TaskItem(
                title: "Morning Exercise Routine",
                description: "30 minutes of cardio and strength training",
                priority: .high,
                status: .pending,
                dueDate: Date(),
                category: .health
            ),
            TaskItem(
                title: "Plan Weekend Trip",
                description: "Research destinations and book accommodations",
                priority: .low,
                status: .pending,
                dueDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
                category: .personal
            ),
            TaskItem(
                title: "Test App Features",
                description: "Thoroughly test all app functionality before submission",
                priority: .high,
                status: .completed,
                dueDate: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
                category: .work
            ),
            TaskItem(
                title: "Read Technical Documentation",
                description: "Study iOS development best practices and design patterns",
                priority: .medium,
                status: .pending,
                dueDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()),
                category: .study
            )
        ]
        
        // Set completion dates for completed tasks
        for var task in demoTasks {
            if task.status == .completed {
                task.isCompleted = true
                task.completedDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())
            }
            tasks.append(task)
        }
        
        // Mark demo data as setup
        UserDefaults.standard.set(true, forKey: demoKey)
        saveTasks()
        
        // Setup some initial progress for achievements and growth
        if tasks.filter({ $0.isCompleted }).count > 0 {
            // Award some initial points
            growthManager.awardPointsForTaskCompletion(priority: .high)
            growthManager.awardPointsForTaskCompletion(priority: .medium)
            
            // Update completed tasks count
            let completedCount = tasks.filter { $0.isCompleted }.count
            growthManager.updateCompletedTasksCount(completedCount)
            
            // Initialize streak
            streakManager.taskCompleted()
            
            // Update achievement progress
            achievementManager.updateProgress()
        }
        
        print("DEBUG: Demo data setup complete for reviewer account - \(demoTasks.count) tasks created")
    }
    
    func forceSaveTasks() {
        print("DEBUG: Force saving tasks...")
        saveTasks()
    }
    
    func clearAllTasks() {
        print("DEBUG: Clearing all tasks for current user")
        tasks.removeAll()
        saveTasks()
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let pointsChanged = Notification.Name("pointsChanged")
}