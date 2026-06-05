import Foundation

/// Builds a CSV backup of all logged history for sharing/export. Each export
/// gets a timestamped filename so successive backups don't overwrite each
/// other when saved to Files/iCloud Drive.
enum CSVExport {
    static func makeFile(from exercises: [Exercise]) -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var rows = ["Exercise,Unit,Date,Value"]
        for exercise in exercises.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            let name = exercise.name.replacingOccurrences(of: ",", with: " ")
            for entry in exercise.sortedEntries {
                rows.append("\(name),\(exercise.unit),\(dateFormatter.string(from: entry.date)),\(entry.value.clean)")
            }
        }

        let csv = rows.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename())
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func filename() -> String {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd-HHmm"
        stamp.locale = Locale(identifier: "en_US_POSIX")
        return "GymTrack-\(stamp.string(from: Date())).csv"
    }
}
