import Foundation
import SwiftUI

enum LogLevel: String, CaseIterable, Identifiable {
    case debug
    case info
    case warning
    case error

    var id: String { rawValue }

    var priority: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .green
        case .warning: return .yellow
        case .error: return .red
        }
    }

    var prefix: String {
        switch self {
        case .debug: return "[DEBUG]"
        case .info: return "[INFO]"
        case .warning: return "[WARN]"
        case .error: return "[ERROR]"
        }
    }
}

final class DebugLog: ObservableObject, @unchecked Sendable {
    static let shared = DebugLog()

    private let logQueue: DispatchQueue = DispatchQueue(label: "Logs")

    struct Entry: Identifiable, Hashable {
        let id = UUID()
        let level: LogLevel
        let message: String
        let timestamp: Date
    }

    @Published private(set) var messages: [Entry] = []
    var minimumLevel: LogLevel = .info

    private init() {}

    /// Thread-safe public logging method
    func log(_ text: String, level: LogLevel = .info) {
        let entry: DebugLog.Entry = Entry(level: level, message: text, timestamp: Date())

        // always print to console immediately (non-UI)
        print("\(entry.level.prefix) \(entry.message)")
        // update the observable messages safely
        logQueue.async {
            self.messages.append(entry)
        }
    }

    /// Thread-safe public change log level method
    func setMinimumLevel(level: LogLevel) {
        logQueue.async {
            self.minimumLevel = level
        }
    }

    func clear() {
        messages.removeAll()
    }
}

struct DebugOverlay: View {
    @ObservedObject var logger: DebugLog = .shared
    private let dateFormatter: DateFormatter = {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var filteredMessages: [DebugLog.Entry] {
        logger.messages.filter {
            $0.level.priority >= logger.minimumLevel.priority
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(filteredMessages) { entry in

                    Text("\(entry.level.prefix) \(entry.timestamp, formatter: dateFormatter) \(entry.message)")
                        .font(.caption2)
                        .foregroundColor(entry.level.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(6)
        }
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
        .padding()
    }
}
