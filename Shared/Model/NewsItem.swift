import Foundation

struct NewsItem: Identifiable, Codable, Hashable {
    var id: String { link }
    var title: String
    var link: String
    var source: String
    var date: Date?
    /// Magyar vagy angol — a felület jelzi, hogy ne érjen meglepetés.
    var language: String = "hu"
    /// Miért került be — ezt a felület kiírja, hogy ne legyen találomra válogatott lista.
    var reason: Reason
    /// Egy soros összefoglaló a csatornából (`<description>`). A dizájn
    /// kéri, de nem találunk ki: ha a forrás nem ad, nem jelenik meg.
    var summary: String?
    /// Vezető kép a csatornából (`<enclosure>` / `<media:content>`).
    var imageURL: String?
    /// Ha az alapod egyik nagy tételéről szól, annak a NEVE — pontosan úgy,
    /// ahogy a `FundComposition` szeletében szerepel. A hírek fül ez alapján
    /// teszi a hírt a megfelelő papír alá.
    var holding: String?

    enum Reason: String, Codable {
        case forint   // a devizahatásodat magyarázza
        case market   // a részvénypiacot érinti
        case holding  // konkrétan az alapod egyik nagy tételéről szól
    }
}
