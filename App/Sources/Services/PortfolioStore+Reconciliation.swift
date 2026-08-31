import Foundation

extension PortfolioStore {

    /// A „miért más a szolgáltató és az app?” képernyő számítási alapja.
    ///
    /// Ez nem próbálja kitalálni a bróker által kijelzett élő árat. Ehelyett
    /// a nálunk lévő forrásokat, hiányzó adatokat és a számítási kockázatokat
    /// teszi láthatóvá. Így egy eltérés nem marad néma, és nem keverjük össze
    /// a régi kivonatot a friss piaci jegyzéssel.
    var reconciliationReport: ReconciliationReport {
        var issues: [ReconciliationIssue] = []
        var rows: [ReconciliationRow] = []
        let summaries = platformSummaries

        if !holdings.isEmpty, fxRate <= 0 {
            issues.append(ReconciliationIssue(
                id: "portfolio.missing-fx",
                severity: .critical,
                title: "Hiányzik az EUR/HUF árfolyam",
                detail: "Az értékpapírok forintosított értéke addig nem teljes, amíg nincs érvényes devizaárfolyam."
            ))
        }

        for summary in summaries {
            let id = summary.platform.id
            var rowSeverity: ReconciliationSeverity = .clear
            var details: [String] = []
            let ownHoldings = holdings.filter { $0.account == id }

            if hasMissingQuotes(platformID: id) {
                let missing = ownHoldings.filter { quotes[$0.isin] == nil }
                    .map(\.ticker).joined(separator: ", ")
                let issue = ReconciliationIssue(
                    id: "platform.missing-quote.\(id)",
                    severity: .critical,
                    title: "Hiányzó árfolyam: \(summary.platform.name)",
                    detail: "Ezekhez nincs élő jegyzés: \(missing). A kijelzett érték csak a maradék adatot tartalmazza."
                )
                issues.append(issue)
                rowSeverity = max(rowSeverity, issue.severity)
                details.append("\(missing) árfolyama hiányzik")
            }

            if ownHoldings.contains(where: { $0.costHUF == nil }) {
                let issue = ReconciliationIssue(
                    id: "platform.missing-cost.\(id)",
                    severity: .warning,
                    title: "Hiányos bekerülési érték: \(summary.platform.name)",
                    detail: "A forintos bekerülési ár nem áll rendelkezésre minden pozícióhoz, ezért a hozam bontása korlátozott."
                )
                issues.append(issue)
                rowSeverity = max(rowSeverity, issue.severity)
                details.append("nincs teljes HUF bekerülési érték")
            }

            for holding in ownHoldings where holding.quantity > 1_000_000 {
                let issue = ReconciliationIssue(
                    id: "holding.suspicious-quantity.\(holding.id.uuidString)",
                    severity: .critical,
                    title: "Szokatlanul nagy darabszám: \(holding.ticker)",
                    detail: "\(Fmt.decimal(holding.quantity, max: 6)) darab szerepel. Ellenőrizd az importot, mielőtt a portfólióértéket elfogadod."
                )
                issues.append(issue)
                rowSeverity = max(rowSeverity, issue.severity)
                details.append("\(holding.ticker) darabszáma ellenőrizendő")
            }

            let assets = cashAssets.filter { $0.platform == id }
            for asset in assets {
                let days = asset.daysSinceStatement()
                if days >= 30 {
                    let issue = ReconciliationIssue(
                        id: "platform.stale-balance.\(asset.id.uuidString)",
                        severity: .critical,
                        title: "Régi egyenleg: \(asset.name)",
                        detail: "Az utolsó kivonat \(days) napos. A kijelzett érték nem tekinthető friss mérésnek."
                    )
                    issues.append(issue)
                    rowSeverity = max(rowSeverity, issue.severity)
                    details.append("\(days) napos egyenleg")
                } else if days >= 7 {
                    let issue = ReconciliationIssue(
                        id: "platform.stale-balance.\(asset.id.uuidString)",
                        severity: .warning,
                        title: "Nem friss egyenleg: \(asset.name)",
                        detail: "Az utolsó kivonat \(days) napos; érdemes új exportot beolvasni."
                    )
                    issues.append(issue)
                    rowSeverity = max(rowSeverity, issue.severity)
                    details.append("\(days) napos egyenleg")
                }
            }

            if summary.platform.kind == .crypto {
                let positions = cryptoPositions.filter { $0.platform == id }
                if positions.contains(where: { $0.asOf == nil }) {
                    let issue = ReconciliationIssue(
                        id: "platform.crypto-no-date.\(id)",
                        severity: .warning,
                        title: "Kripto-export dátuma hiányzik",
                        detail: "Az érték csak az export pillanatára tekinthető mérésnek; olvasd be újra dátummal ellátott exportból."
                    )
                    issues.append(issue)
                    rowSeverity = max(rowSeverity, issue.severity)
                    details.append("hiányzik az export dátuma")
                }
                if positions.contains(where: { $0.currentValueHUF <= 0 }) {
                    let issue = ReconciliationIssue(
                        id: "platform.crypto-zero-value.\(id)",
                        severity: .warning,
                        title: "Nulla értékű kripto-sor",
                        detail: "A nulla értékű sor nem adható hozzá a nettó vagyonhoz; ellenőrizd az export szűrését."
                    )
                    issues.append(issue)
                    rowSeverity = max(rowSeverity, issue.severity)
                    details.append("nulla értékű sor")
                }
            }

            // MÁK imports keep both the aggregate balance and the individual
            // security rows. Compare them here so a changed export layout or
            // a duplicated total row cannot silently inflate the portfolio.
            if id.hasPrefix("treasury-") {
                let detailed = treasuryPositions
                    .filter { $0.id.hasPrefix("\(id):") }
                    .reduce(Decimal(0)) { $0 + $1.currentValueHUF }
                if detailed > 0 {
                    let difference = abs(summary.valueHUF - detailed)
                    if difference > 1 {
                        let issue = ReconciliationIssue(
                            id: "platform.treasury-total-mismatch.\(id)",
                            severity: .critical,
                            title: "Eltér a WebKincstár részlete és végösszege",
                            detail: "A sorok összege \(Fmt.huf(detailed)), a mentett végösszeg \(Fmt.huf(summary.valueHUF)); különbség \(Fmt.huf(difference))."
                        )
                        issues.append(issue)
                        rowSeverity = max(rowSeverity, issue.severity)
                        details.append("a részletek és a végösszeg nem egyeznek")
                    }
                }
            }

            if summary.isMissingValue {
                let issue = ReconciliationIssue(
                    id: "platform.incomplete-value.\(id)",
                    severity: .critical,
                    title: "Nem teljes érték: \(summary.platform.name)",
                    detail: "A platformhoz tartozó egyenleg vagy valamelyik árfolyam hiányzik, ezért a hozam nem értelmezhető."
                )
                issues.append(issue)
                rowSeverity = max(rowSeverity, issue.severity)
                details.append("hiányos érték")
            }

            let change: Decimal?
            if summary.platform.hasMeaningfulGain, summary.depositsHUF > 0 {
                change = summary.valueHUF - summary.depositsHUF
            } else {
                change = nil
            }

            rows.append(ReconciliationRow(
                id: id,
                platformName: summary.platform.name,
                source: reconciliationSource(for: summary.platform),
                valueHUF: summary.valueHUF,
                depositsHUF: summary.depositsHUF > 0 ? summary.depositsHUF : nil,
                changeHUF: change,
                severity: rowSeverity,
                detail: details.isEmpty ? "A tárolt adatok és a számítási lánc rendben." : details.joined(separator: " · ")
            ))
        }

        if let unmatched = unmatchedTransfers {
            issues.append(ReconciliationIssue(
                id: "portfolio.unmatched-transfers",
                severity: .warning,
                title: "Nem párosított átvezetés",
                detail: "\(Fmt.huf(abs(unmatched.netHUF))) eltérés maradt a következő számlák között: \(unmatched.accounts.joined(separator: ", "))."
            ))
        }

        return ReconciliationReport(
            generatedAt: Date(),
            rows: rows,
            issues: issues.sorted { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        )
    }

    private func reconciliationSource(for platform: Platform) -> String {
        if let bank = bankLinkedPlatforms[platform.id] {
            return "Bankkapcsolat · \(bank)"
        }
        let normalized = platform.name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        if platform.id.hasPrefix("treasury-") || normalized.contains("allamkincstar") {
            return "WebKincstár export"
        }
        if platform.kind == .crypto { return "Kripto/wallet export" }
        if platform.kind == .brokerage { return "Értékpapír-kivonat" }
        return "Helyi import"
    }
}
