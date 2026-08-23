import Foundation

private final class FixtureBundleToken: NSObject {}

enum FixtureLoader {
    static func data(named name: String, fileExtension: String? = nil,
                     subdirectory: String? = nil,
                     file: StaticString = #filePath,
                     line: UInt = #line) throws -> Data {
        let resourceExtension = fileExtension ?? "json"
        let bundle = Bundle(for: FixtureBundleToken.self)
        let bundledURL = bundle.url(forResource: name, withExtension: resourceExtension,
                                    subdirectory: subdirectory)
            ?? bundle.url(forResource: name, withExtension: resourceExtension)

        // Source-path fallback keeps the helper useful for command-line
        // inspection and for Xcode builds that have not copied resources yet.
        let testFile = URL(fileURLWithPath: String(describing: file))
        let sourceDirectory = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let directory = subdirectory.map { sourceDirectory.appendingPathComponent($0) }
            ?? sourceDirectory
        let sourceURL = directory.appendingPathComponent(name)
            .appendingPathExtension(resourceExtension)
        let url = bundledURL ?? sourceURL
        return try Data(contentsOf: url)
    }

    static func string(named name: String, fileExtension: String? = nil,
                       subdirectory: String? = nil,
                       file: StaticString = #filePath,
                       line: UInt = #line) throws -> String {
        let data = try self.data(named: name, fileExtension: fileExtension,
                                 subdirectory: subdirectory, file: file, line: line)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "FixtureLoader", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Fixture is not UTF-8"])
        }
        return string
    }
}
