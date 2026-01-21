//
//  PomodoroManager.swift
//  FocusMate
//
//  Created by Guanheng Wang on 08/08/2025.
//

import SwiftUI
import Combine

// MARK: - Pomodoro Manager
class PomodoroManager: ObservableObject {
    @Published var timerRunning = false
    @Published var timeRemaining = 25 * 60 // 25 minutes in seconds
    @Published var currentPomodoro = 1
    @Published var showBreakTimer = false
    @Published var breakTimeRemaining = 5 * 60 // 5 minutes in seconds
    @Published var focusDuration = 25 // minutes
    @Published var breakDuration = 5 // minutes
    
    private var timer: AnyCancellable?
    private var backgroundTime: Date?
    private let baseUserDefaultsKey = "PomodoroState"
    private var currentUserId: String?
    
    // Track when pomodoro completion happens to prevent duplicate point awards
    private var lastPomodoroCompletionTime: Date?
    
    init(userId: String? = nil) {
        self.currentUserId = userId
        // Always start with default 25-minute focus duration
        focusDuration = 25
        breakDuration = 5
        timeRemaining = 25 * 60
        breakTimeRemaining = 5 * 60
        loadState()
        setupTimer()
    }
    
    // MARK: - User Management
    
    func setCurrentUser(_ userId: String) {
        self.currentUserId = userId
        loadState()
    }
    
    func clearCurrentUser() {
        // Save current user data before clearing
        if currentUserId != nil {
            saveState()
        }
        
        self.currentUserId = nil
        // Reset to default state
        timerRunning = false
        timeRemaining = 25 * 60
        currentPomodoro = 1
        showBreakTimer = false
        breakTimeRemaining = 5 * 60
        focusDuration = 25
        breakDuration = 5
    }
    
    private func getUserSpecificKey(_ baseKey: String) -> String {
        if let userId = currentUserId {
            return "\(baseKey)_\(userId)"
        }
        return baseKey
    }
    
    deinit {
        saveState()
        timer?.cancel()
    }
    
    // MARK: - Timer Management
    
    private func setupTimer() {
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                self?.updateTimer()
            }
    }
    
    private func updateTimer() {
        if timerRunning && timeRemaining > 0 {
            timeRemaining -= 1
        } else if timeRemaining == 0 && !showBreakTimer {
            // Focus session completed
            timerRunning = false
            showBreakTimer = true
            breakTimeRemaining = breakDuration * 60
            lastPomodoroCompletionTime = Date() // Record when pomodoro completed
            saveState()
        } else if showBreakTimer && breakTimeRemaining > 0 {
            breakTimeRemaining -= 1
        } else if showBreakTimer && breakTimeRemaining == 0 {
            // Break completed
            showBreakTimer = false
            currentPomodoro += 1
            resetTimer()
        }
    }
    
    // MARK: - Public Methods
    
    func startTimer() {
        timerRunning = true
        saveState()
    }
    
    func stopTimer() {
        timerRunning = false
        saveState()
    }
    
    func resetTimer() {
        timeRemaining = focusDuration * 60
        breakTimeRemaining = breakDuration * 60
        timerRunning = false
        showBreakTimer = false
        saveState()
    }
    
    func updateDurations(focus: Int, breakDuration: Int) {
        focusDuration = focus
        self.breakDuration = breakDuration
        
        // Update current timer if it's running
        if timerRunning && !showBreakTimer {
            // Calculate remaining time ratio and apply to new duration
            let totalOriginalTime = (self.focusDuration * 60)
            let remainingRatio = Double(timeRemaining) / Double(totalOriginalTime)
            timeRemaining = Int(Double(focus * 60) * remainingRatio)
        } else if showBreakTimer {
            // Update break timer if in break mode
            let totalOriginalBreakTime = (self.breakDuration * 60)
            let remainingBreakRatio = Double(breakTimeRemaining) / Double(totalOriginalBreakTime)
            breakTimeRemaining = Int(Double(breakDuration * 60) * remainingBreakRatio)
        } else {
            // If timer is not running, reset to new duration
            timeRemaining = focus * 60
        }
        
        saveState()
    }
    
    // Get the time when the last pomodoro completed
    func getLastPomodoroCompletionTime() -> Date? {
        return lastPomodoroCompletionTime
    }
    
    // MARK: - State Persistence
    
    private func saveState() {
        let state = PomodoroState(
            timerRunning: timerRunning,
            timeRemaining: timeRemaining,
            currentPomodoro: currentPomodoro,
            showBreakTimer: showBreakTimer,
            breakTimeRemaining: breakTimeRemaining,
            focusDuration: focusDuration,
            breakDuration: breakDuration,
            lastUpdateTime: Date()
        )
        
        let key = getUserSpecificKey(baseUserDefaultsKey)
        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    private func loadState() {
        let key = getUserSpecificKey(baseUserDefaultsKey)
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(PomodoroState.self, from: data) else {
            // No saved state, ensure we use default 25-minute focus duration
            focusDuration = 25
            breakDuration = 5
            timeRemaining = 25 * 60
            return
        }
        
        // Always reset timer state when app reopens for better user experience
        // Users expect a fresh start when they reopen the app
        focusDuration = 25
        breakDuration = 5
        timeRemaining = 25 * 60
        breakTimeRemaining = 5 * 60
        timerRunning = false
        showBreakTimer = false
        currentPomodoro = 1
        
        print("DEBUG: PomodoroManager - Reset to default state on app reopen")
    }
    
    // MARK: - Background Handling
    
    func handleAppBackground() {
        backgroundTime = Date()
        saveState()
    }
    
    func handleAppForeground() {
        guard let backgroundTime = backgroundTime else { return }
        let elapsedTime = Date().timeIntervalSince(backgroundTime)
        
        if timerRunning && !showBreakTimer {
            let elapsedSeconds = Int(elapsedTime)
            timeRemaining = max(0, timeRemaining - elapsedSeconds)
            if timeRemaining == 0 {
                timerRunning = false
                showBreakTimer = true
                breakTimeRemaining = breakDuration * 60
            }
        } else if showBreakTimer {
            let elapsedSeconds = Int(elapsedTime)
            breakTimeRemaining = max(0, breakTimeRemaining - elapsedSeconds)
            if breakTimeRemaining == 0 {
                showBreakTimer = false
                currentPomodoro += 1
                resetTimer()
            }
        }
        
        self.backgroundTime = nil
        saveState()
    }
}

// MARK: - Pomodoro State
struct PomodoroState: Codable {
    let timerRunning: Bool
    let timeRemaining: Int
    let currentPomodoro: Int
    let showBreakTimer: Bool
    let breakTimeRemaining: Int
    let focusDuration: Int
    let breakDuration: Int
    let lastUpdateTime: Date
}
