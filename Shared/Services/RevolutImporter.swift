import Foundation

/// A két magyar Revolut-kivonat beolvasója.
///
/// A formátumok érdemben eltérnek, ezért fejléc alapján ismerjük fel őket:
///
/// **Megtakarítási** (`savings-statement_*.csv`)
///   `Dátum,Leírás,Nettó kamatláb|EBKM,Bejövő összeg,Kimenő összeg,Egyenleg`
///   Magyar dátum, vesszős tizedes, pénznem-utótag. A fájlban **KÉT fejléc**
///   is előfordul (a harmadik oszlop neve menet közben `Nettó kamatláb`-ról
///   `EBKM`-re vált) — ezért minden „Dátum"-mal kezdődő sort fejlécnek veszünk,
///   nem csak az elsőt.
///
/// **Folyószámla** (`account-statement_*.csv`)
///   `Típus,Termék,Kezdés dátuma,Teljesítés dátuma,Leírás,Összeg,Díj,Pénznem,State,Egyenleg`
///   ISO dátum, pontos tizedes, előjeles összeg.
///   **Az `Egyenleg` oszlop TERMÉKENKÉNT értendő**: a `Termék=Befizetés`
///   sorok a megtakarítási egyenleget mutatják, nem a folyószámláét. Aki
///   globálisan olvassa, rossz egyenleget kap.
struct RevolutImporter {

    struct Result {
        var platform: Platform
        var asset: CashAsset
        var deposits: [Deposit]
        var fees: [FeeItem]
        /// NAPI záró egyenleg a kivonatból. A Revolut minden sorhoz kiírja az
        /// egyenleget, tehát a teljes időszak görbéje benne van a fájlban —
        /// nem kell megvárni, hogy az app napról napra összemérje.
        var dailyBalances: [Date: Decimal]
        var warnings: [String]
    }

    enum Kind { case savings, account }

    static func detect(csv text: String) -> Kind? {
        guard let header = text.split(whereSeparator: \.isNewline).first else { return nil }
        if header.contains("Bejövő összeg"), header.contains("Egyenleg") { return .savings }
        if header.contains("Típus"), header.contains("Termék"), header.contains("State") {
            return .account
        }
        return nil
    }

    // MARK: - Megtakarítási számla

    static func importSavings(csv text: String, platformID: String) -> Result {
        var deposits: [Deposit] = []
        var warnings: [String] = []
        var balance: Decimal = 0
        var interest: Decimal = 0
        var latestRate: Double?
        var lastDate: Date?
        var unknown = 0
        /// (jóváírt kamat, az AZ ELŐTTI egyenleg) párok — ebből mérjük a
        /// tényleges nettó napi kulcsot. A meghirdetett EBKM-et nem
        /// használhatjuk: a jóváírt összeg annak csak ~72%-a.
        var interestSamples: [(interest: Decimal, base: Decimal)] = []
        var dailyBalances: [Date: Decimal] = [:]
        // A kivonat nem a számla nyitásától szól: az első sor egyenlegéből
        // vissza kell fejteni a nyitó összeget, különben az a pénz hozamnak
        // látszana.
        //
        // KÜLSŐ tételként vesszük fel, nem belsőként. A nyitó egyenleg a
        // megfigyelt időszak ELŐTT került a számlára — tőke, nem hozam.
        // Belsőként jelölve kimaradna az összesített befizetésből, és pont
        // annyival mutatna több nyereséget, amennyi a nyitó összeg volt.
        var openingRecorded = false

        for line in text.split(whereSeparator: \.isNewline) {
            let f = StatementImporter.parse(line: String(line))
            guard f.count >= 6 else { continue }
            // Minden fejléc-sort átugrunk, nem csak az elsőt.
            guard f[0] != "Dátum", let date = HungarianCSV.hungarianDate(f[0]) else { continue }

            let description = f[1]
            let rateText = f[2].trimmingCharacters(in: .whitespaces)
            let incoming = HungarianCSV.amount(f[3])
            let outgoing = HungarianCSV.amount(f[4])
            lastDate = date
            let closingAmount = HungarianCSV.amount(f[5])
            // Napon belül több tétel is lehet; a KÉSŐBBI felülírja, így a nap
            // végi egyenleg marad.
            if let closing = closingAmount { dailyBalances[date] = closing.value }
            if let closing = closingAmount { balance = closing.value }

            if !openingRecorded, let closing = closingAmount {
                let movement = (incoming?.value ?? 0) - (outgoing?.value ?? 0)
                let opening = closing.value - movement
                if opening != 0 {
                    deposits.append(Deposit(account: platformID, date: date,
                                            amountHUF: opening, isInternal: false))
                }
                openingRecorded = true
            }

            if let percent = rateText.hasSuffix("%")
                ? Double(rateText.dropLast().replacingOccurrences(of: ",", with: "."))
                : nil {
                latestRate = percent
            }

            let lower = description.lowercased()
            if lower.contains("kamat") {
                // A kamat HOZAM, nem befizetés. Ha befizetésként vennénk, a
                // hozam pont annyival tűnne el, amennyit a kamat hozott.
                let credited = incoming?.value ?? 0
                interest += credited
                // A kamat előtti egyenleg = záró − jóváírt.
                if let closing = closingAmount?.value, credited > 0 {
                    let base = closing - credited
                    if base > 0 { interestSamples.append((credited, base)) }
                }
            } else if description.hasPrefix("Befizetés ide") {
                // Belső mozgás: a pénz a folyószámláról jön, nem kívülről.
                deposits.append(Deposit(account: platformID, date: date,
                                        amountHUF: incoming?.value ?? 0, isInternal: true))
            } else if description.hasPrefix("Pénzkivétel innen") {
                // Kivét = negatív befizetés, így az XIRR helyesen számol.
                deposits.append(Deposit(account: platformID, date: date,
                                        amountHUF: -(outgoing?.value ?? 0), isInternal: true))
            } else {
                unknown += 1
            }
        }

        if unknown > 0 {
            warnings.append("\(unknown) ismeretlen sor a megtakarítási kivonatban — kimaradt.")
        }
        if interest > 0 {
            warnings.append("Jóváírt kamat az időszakban: \(Fmt.huf(interest)).")
        }

        let platform = Platform(id: platformID, name: "Revolut Savings",
                                kind: .savings, accent: .lilac, monogram: "RS")
        // A LEGUTÓBBI néhány jóváírásból mérünk: a kulcs az időszakon belül is
        // változhat (a mintában 1,25% → 2,49% → 2,50%), ezért a régi napok
        // átlagba vétele elavult kulcsot adna.
        let recent = interestSamples.suffix(7)
        let netDaily: Decimal? = recent.isEmpty ? nil
            : recent.reduce(Decimal(0)) { $0 + $1.interest / $1.base } / Decimal(recent.count)

        if let netDaily {
            let annual = netDaily.doubleValue * 365 * 100
            warnings.append(String(format: "Mért nettó kamat: %.2f%% évesítve (a meghirdetett EBKM-nél alacsonyabb a levonás miatt). Az app ezzel becsüli a napi gyarapodást két import között.", annual))
        }

        let asset = CashAsset(platform: platformID, name: "Megtakarítási Számla",
                              balance: balance, currency: "HUF",
                              annualRatePct: latestRate, asOf: lastDate,
                              netDailyRate: netDaily)
        return Result(platform: platform, asset: asset, deposits: deposits,
                      fees: [], dailyBalances: dailyBalances, warnings: warnings)
    }

    // MARK: - Folyószámla

    static func importAccount(csv text: String, platformID: String) -> Result {
        var deposits: [Deposit] = []
        var fees: [FeeItem] = []
        var warnings: [String] = []
        var balance: Decimal = 0
        var skippedPending = 0

        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let header = lines.first else {
            return Result(platform: Platform(id: platformID, name: "Revolut Folyószámla",
                                             kind: .current, accent: .mint, monogram: "RF"),
                          asset: CashAsset(platform: platformID, name: "Folyószámla",
                                           balance: 0, currency: "HUF"),
                          deposits: [], fees: [], dailyBalances: [:],
                          warnings: ["Üres fájl."])
        }
        let columns = StatementImporter.parse(line: header)
        let index = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($1, $0) })

        func field(_ f: [String], _ name: String) -> String {
            guard let i = index[name], i < f.count else { return "" }
            return f[i]
        }

        // A kivonat nem a számla nyitásától szól, ezért a NYITÓ egyenleget
        // vissza kell számolni az első sorból: egyenleg − az a mozgás.
        // Enélkül a számla úgy nézne ki, mintha a nyitó pénz hozam lenne.
        var openingRecorded = false
        var lastAccountDate: Date?
        var dailyBalances: [Date: Decimal] = [:]

        for line in lines.dropFirst() {
            let f = StatementImporter.parse(line: line)
            guard f.count >= columns.count else { continue }

            // Csak a teljesült tételek. A függőben lévő és a visszatérített
            // sorok beszámítása kétszer mozgatná az egyenleget.
            guard field(f, "State") == "ELVÉGEZVE" else { skippedPending += 1; continue }
            guard field(f, "Termék") == "Folyószámla" else { continue }

            // FIGYELEM: ez a fájl PONTOS tizedesjelet használ, nem vesszőset.
            let amount = HungarianCSV.plainAmount(field(f, "Összeg")) ?? 0
            let closing = HungarianCSV.plainAmount(field(f, "Egyenleg"))
            let date = HungarianCSV.isoFormatter.date(from: field(f, "Teljesítés dátuma"))
                ?? HungarianCSV.isoFormatter.date(from: field(f, "Kezdés dátuma"))
            guard let date else { continue }

            if let closing {
                balance = closing
                lastAccountDate = date
                dailyBalances[Calendar.current.startOfDay(for: date)] = closing
            }

            if !openingRecorded, let closing {
                let opening = closing - amount
                if opening != 0 {
                    deposits.append(Deposit(account: platformID, date: date,
                                            amountHUF: opening, isInternal: false))
                }
                openingRecorded = true
            }

            // MINDEN mozgás befizetésként (előjelesen) kerül be. Így a
            // készpénzszámla hozama pontosan nulla lesz — ami igaz is: egy
            // költési számla nem termel. Enélkül a betett pénz hozamnak
            // látszana, a elköltött pedig veszteségnek.
            //
            // A megtakarításba/ból mozgatott pénz BELSŐ: a platform saját
            // mérlegében benne van, de a teljes vagyon befizetéséből kimarad,
            // különben ugyanaz a forint kétszer számítana.
            let fee = HungarianCSV.plainAmount(field(f, "Díj")) ?? 0
            if fee > 0 {
                fees.append(FeeItem(account: platformID, date: date,
                                    amountHUF: fee, kind: .trade))
            }

            let isInternal = field(f, "Leírás").contains("Megtakarítási Számla")
            // A DÍJ is levonódik az egyenlegből, külön az összegtől — ezt
            // mértük a kivonaton (−499,52 összeg + 5,00 díj → −504,52 egyenlegváltozás).
            // Ezért a pénzáramba a díjjal csökkentett összeg megy: így a
            // készpénzszámla „hozama" pontosan nulla, ami igaz is. A díjak
            // külön tételként továbbra is látszanak.
            deposits.append(Deposit(account: platformID, date: date,
                                    amountHUF: amount - fee, isInternal: isInternal))
        }

        if skippedPending > 0 {
            warnings.append("\(skippedPending) függőben lévő vagy visszatérített tétel kihagyva.")
        }
        warnings.append("A folyószámla költési számla — az app az egyenlegét tartja nyilván, a költéseidet nem elemzi.")

        let platform = Platform(id: platformID, name: "Revolut Folyószámla",
                                kind: .current, accent: .mint, monogram: "RF")
        let asset = CashAsset(platform: platformID, name: "Folyószámla",
                              balance: balance, currency: "HUF",
                              annualRatePct: nil, asOf: lastAccountDate)
        return Result(platform: platform, asset: asset, deposits: deposits,
                      fees: fees, dailyBalances: dailyBalances, warnings: warnings)
    }
}
