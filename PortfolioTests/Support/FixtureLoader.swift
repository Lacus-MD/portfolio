import Foundation

enum FixtureLoader {
    static func data(named name: String, extension: String? = nil,
                     subdirectory: String? = nil,
                     file: StaticString = #filePath,
                     line: UInt = #line) throws -> Data {
        let testFile = URL(fileURLWithPath: String(describing: file))
        let testsDirectory = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureDirectory = testsDirectory.appendingPathComponent("Fixtures")
        let directory = subdirectory.map { fixtureDirectory.appendingPathComponent($0) }
            ?? fixtureDirectory
        let url = directory.appendingPathComponent(name)
            .appendingPathExtension(`extension` ?? "json")
        return try Data(contentsOf: url)
    }
}
