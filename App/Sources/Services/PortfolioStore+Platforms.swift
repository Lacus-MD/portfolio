import Foundation

/// Egy platform összesített állapota — a kezdőképernyő kártyái és az
/// összehasonlító nézet ebből dolgozik.
struct PlatformSummary: Identifiable, Hashable {
    /// Igaz, ha a hozam nem SZÁMOLHATÓ, mert hiányzik hozzá adat.
    ///
    /// Két esete van, és mindkettőt mértük:
    ///   • van befizetés, de nincs érték — a kivonat egyik fele hiányzik;
    ///   • van értékpapír, de valamelyikhez még nincs árfolyam — ilyenkor a
    ///     számla csak a maradék készpénzt éri, és a felület „−99,92%"-ot
    ///     írna ki abból, hogy a hálózat még nem válaszolt;
    ///   • egy KAMATOZÓ számla értéke a befizetés felénél kisebb — kamatozó
    ///     számla nem veszíthet pénzt, tehát ez nem veszteség, hanem hibás
    ///     vagy hiányzó egyenleg a kivonatból.
    /// Az érték nullához mérése önmagában kevés: pár száz forint bennragadt
    /// készpénz már „nem nulla", és kivédi az őrt.
    var isMissingValue: Bool

    var platform: Platform
    var id: String { platform.id }
    var valueHUF: Decimal
    var depositsHUF: Decimal
    var gainHUF: Decimal
    var gainPct: Double
    /// Részesedés a teljes pénzügyi állomány abszolút értékéből, 0…1.
    /// A tartozás is pozitív ívhosszt kap; a piros szín mondja el, hogy
    /// kötelezettség, nem az előjel eltüntetése.
    var share: Double
}

extension PortfolioStore {

    /// A követett platformok. Ha nincs kézzel megadott lista, a pozíciók és a
    /// készpénz-eszközök számláiból származtatjuk, hogy a felület sose legyen
    /// üres pusztán azért, mert a platformokat még nem neveztük el.
    /// A jelenlegi állapot a KÖZÖS matek alakjában.
    ///
    /// A számítás nem itt él, hanem a `PortfolioMath`-ban, mert a widgetnek is
    /// kell — és amíg két helyen volt, el is csúsztak: a widget csak az
    /// értékpapírokból számolt, euróban, a bekerülési árhoz mérve.
    var mathPayload: PortfolioFile.Payload {
        var payload = PortfolioFile.Payload()
        payload.holdings = holdings
        payload.deposits = deposits
        payload.platforms = platforms
        payload.cashAssets = cashAssets
        payload.cash = cash
        payload.conversionSpread = conversionSpread
        payload.snapshots = snapshots
        return payload
    }

    var mathPrices: PortfolioMath.Prices {
        .init(quotes: quotes.mapValues(\.price), fxRate: fxRate, usdRate: usdRate)
    }

    /// A követett platformok. Ha nincs kézzel megadott lista, a pozíciók és a
    /// készpénz-eszközök számláiból származtatjuk, hogy a felület sose legyen
    /// üres pusztán azért, mert a platformokat még nem neveztük el.
    var resolvedPlatforms: [Platform] {
        PortfolioMath.resolvedPlatforms(mathPayload)
    }

    // MARK: - Platformonkénti számok

    func valueHUF(ofPlatform id: String) -> Decimal {
        PortfolioMath.valueHUF(ofPlatform: id, in: mathPayload, prices: mathPrices)
    }

    func depositsHUF(ofPlatform id: String) -> Decimal {
        PortfolioMath.depositsHUF(ofPlatform: id, in: mathPayload)
    }

    func convertToHUF(_ amount: Decimal, currency: String) -> Decimal {
        PortfolioMath.convertToHUF(amount, currency: currency, prices: mathPrices)
    }

    /// Minden platform összesítve.
    ///
    /// Gyorsítótárazva: a kezdőképernyő kilenc külön helyen kéri le, és
    /// mindegyik hívás végigszámolta az összes platform értékét és
    /// befizetését. Görgetés közben ez képkockánként ismétlődött.
    ///
    /// A `derivedStamp` olvasása KÉT dolgot csinál egyszerre: eldönti, hogy
    /// érvényes-e a gyorsítótár, ÉS felépíti a SwiftUI megfigyelését a
    /// mögöttes adatokra. Ez utóbbi nélkül a gyorsítótárból válaszolva a
    /// nézet nem értesülne a változásról, és beragadna a régi számokon.
    var platformSummaries: [PlatformSummary] {
        let stamp = derivedStamp
        if let cache = summariesCache, cache.stamp == stamp { return cache.value }
        let value = computedSummaries
        summariesCache = (stamp, value)
        return value
    }

    /// A befektethető platformok listája: értékpapírszámla és megtakarítás.
    ///
    /// A hitelkártya és folyószámla is pénzügyi adat, de a célallokációnál
    /// ezek már nem befektetések, ezért kizárjuk őket.
    var investablePlatforms: [Platform] {
        resolvedPlatforms.filter(\.hasMeaningfulGain)
    }

    /// A befektethető platformok összesítői.
    var investableSummaries: [PlatformSummary] {
        let ids = Set(investablePlatforms.map(\.id))
        return platformSummaries.filter { ids.contains($0.platform.id) }
    }

    /// Befektethető vagyon: a hozam és új pénztervezés erre számol.
    var investableHUF: Decimal { investableSummaries.reduce(0) { $0 + $1.valueHUF } }

    /// Nem befektethető vagyon: tartozás + folyószámla abszolút értéke.
    var nonInvestableHUF: Decimal {
        resolvedPlatforms.filter { $0.isLiability || $0.isTransactional }
            .reduce(Decimal(0)) { $0 + valueHUF(ofPlatform: $1.id).magnitude }
    }

    private var computedSummaries: [PlatformSummary] {
        let all = resolvedPlatforms
        let values = all.map { valueHUF(ofPlatform: $0.id) }
        // A gyűrűk a TELJES pénzügyi állományon belüli arányt mutatják.
        // A tartozás ezért nem negatív ív (ami eltűnne), hanem a saját
        // abszolút méretével jelenik meg, piros kötelezettségként. A nevező
        // is abszolút: így minden ív 0…1 között marad, és együtt pontosan egy
        // teljes kört adnak ki.
        let totalMagnitude = values.reduce(Decimal(0)) { $0 + abs($1) }

        return zip(all, values).map { platform, value in
            let deposits = depositsHUF(ofPlatform: platform.id)
            let gain = deposits > 0 ? value - deposits : 0
            // Ha nincs érték, a hozam nem nulla mínusz száz százalék, hanem
            // ISMERETLEN — a kivonat egyik fele hiányzik.
            // Kamatozó számla nem veszíthet pénzt: ha az értéke a befizetés
            // felénél kisebb, az adathiba, nem hozam. Ez fogta volna meg a
            // „Revolut Savings −99,90%"-ot, amit a kivonat félreolvasott
            // egyenlege okozott.
            // Tartozásnál a hozam értelmezhetetlen — a kártya a tartozást mutatja.
            // Tartozásnál és FOLYÓSZÁMLÁNÁL a hozam értelmezhetetlen: az
            // egyikre tartozol, a másikra a fizetésed érkezik. Mindkettőnél
            // csak az egyenleg a mondanivaló.
            if !platform.hasMeaningfulGain {
                return PlatformSummary(
                    isMissingValue: false, platform: platform, valueHUF: value,
                    depositsHUF: 0, gainHUF: 0, gainPct: 0,
                    share: totalMagnitude > 0 ? (abs(value) / totalMagnitude).doubleValue : 0)
            }
            let cashBroken = platform.kind == .savings
                && deposits > 0 && value < deposits / 2
            let missing = deposits > 0
                && (value <= 0 || cashBroken || hasMissingQuotes(platformID: platform.id))
            return PlatformSummary(
                isMissingValue: missing,
                platform: platform,
                valueHUF: value,
                depositsHUF: deposits,
                gainHUF: missing ? 0 : gain,
                gainPct: (deposits > 0 && !missing) ? (gain / deposits).doubleValue * 100 : 0,
                share: totalMagnitude > 0 ? (abs(value) / totalMagnitude).doubleValue : 0
            )
        }
        .sorted { a, b in
            // Kézi sorrend, ha van rá bejegyzés. Ami nincs a listában (új
            // platform), az a végére kerül, ÉRTÉK szerint egymás közt —
            // így egy új számla nem tolja szét azt, amit beállítottál.
            let ia = platformOrder.firstIndex(of: a.platform.id)
            let ib = platformOrder.firstIndex(of: b.platform.id)
            switch (ia, ib) {
            case let (x?, y?): return x < y
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return a.valueHUF > b.valueHUF
            }
        }
    }

    // MARK: - Célallokáció

    /// A célallokáció alapértelmezett, érvényes formája.
    ///
    /// - Ha a felhasználónak már van mentett célja, azt használjuk.
    /// - Ha nincs mentett adat, egyenletesen osztunk.
    /// - Mindig 100-ra normalizáljuk.
    func allocationTargetsForEditing() -> [String: Double] {
        var result: [String: Double] = [:]
        let platforms = investablePlatforms
        guard !platforms.isEmpty else { return result }

        let cleaned = allocationTargets.filter { key, _ in
            platforms.contains(where: { $0.id == key })
        }
        let hasCustom = cleaned.values.contains { $0 > 0.0001 }

        for platform in platforms {
            if hasCustom, let value = cleaned[platform.id] {
                result[platform.id] = max(0, min(100, value))
            } else {
                result[platform.id] = 100.0 / Double(platforms.count)
            }
        }
        return normalizeAllocationTargets(result)
    }

    /// Célértékek normalizálása 100%-ra.
    func normalizeAllocationTargets(_ values: [String: Double]) -> [String: Double] {
        let total = values.values.reduce(0, +)
        guard total > 0 else { return values }
        return Dictionary(uniqueKeysWithValues: values.map { (id, value) in
            (id, max(0, min(100, value)) * 100 / total)
        })
    }

    /// Mentett célok frissítése.
    func setAllocationTargets(_ values: [String: Double]) {
        allocationTargets = normalizeAllocationTargets(values)
        save()
    }

    /// Új befizetés cél szerinti felosztási javaslata platformonként.
    ///
    /// Jelenlegi állapot esetén a `delta` alapján oszlik el: amit még az alatta
    /// maradt cél elvár, kap több javaslatot. Ha ez első befizetés (nincs
    /// meglévő összeg), akkor a cél százalékok szerint osztunk.
    func allocationRecommendations(for additionalAmount: Decimal) -> [AllocationSuggestion] {
        guard additionalAmount > 0 else { return [] }
        let summaries = investableSummaries
        guard !summaries.isEmpty else { return [] }
        let targets = allocationTargetsForEditing()
        let totalInvestable = investableHUF.magnitude

        var needsByID: [String: Double] = [:]
        if totalInvestable > 0 {
            for summary in summaries {
                let currentPercent = (summary.valueHUF / totalInvestable * 100).doubleValue
                let targetPercent = targets[summary.platform.id] ?? 0
                needsByID[summary.platform.id] = max(0, targetPercent - currentPercent)
            }
        }

        let totalNeed = needsByID.values.reduce(0, +)
        return summaries.map { summary in
            let targetPercent = targets[summary.platform.id] ?? 0
            let needPercent = totalInvestable > 0 ? (needsByID[summary.platform.id] ?? 0) : targetPercent
            let recommended: Decimal
            if totalInvestable > 0 && totalNeed > 0 {
                recommended = additionalAmount * Decimal(needPercent / totalNeed)
            } else {
                recommended = additionalAmount * Decimal(targetPercent / 100)
            }

            return AllocationSuggestion(
                platformID: summary.platform.id,
                platformName: summary.platform.name,
                platformAccent: summary.platform.accent,
                currentValueHUF: summary.valueHUF,
                targetValueHUF: summary.valueHUF + recommended,
                currentShare: totalInvestable > 0 ? (summary.valueHUF / totalInvestable).doubleValue : 0,
                targetPercent: targetPercent,
                recommendAmount: recommended
            )
        }
        .sorted { $0.recommendAmount > $1.recommendAmount }
    }

    /// A kártyák átrendezése. A `platformSummaries` sorrendjén dolgozunk,
    /// mert a felhasználó AZT látja — nem a nyers platformlistát.
    func movePlatforms(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ids = platformSummaries.map(\.platform.id)
        ids.move(fromOffsets: source, toOffset: destination)
        platformOrder = ids
        save()
    }

    /// Igaz, ha a platformnak van értékpapírja, de valamelyikhez MÉG NINCS
    /// árfolyamunk. Ez nem ugyanaz, mint hogy keveset ér — ilyenkor az érték
    /// ISMERETLEN, és a hozam kiírása félrevezetne.
    func hasMissingQuotes(platformID: String) -> Bool {
        let own = holdings.filter { $0.account == platformID }
        return !own.isEmpty && own.contains { quotes[$0.isin] == nil }
    }

    /// A teljes vagyon minden platformon.
    var grandTotalHUF: Decimal {
        resolvedPlatforms.reduce(Decimal(0)) { $0 + valueHUF(ofPlatform: $1.id) }
    }

    /// Az összesített befizetés csak a KÍVÜLRŐL érkezett pénzt számolja.
    /// A követett platformok közti átvezetés (folyószámla → megtakarítás)
    /// nem új pénz — beszámítva ugyanaz a forint kétszer szerepelne, és a
    /// teljes hozam hamisan romlana.
    /// Az összesített befizetés. A szabály (belső átvezetés nem új pénz, de
    /// a párja nélkül maradt átvezetés igen) a `PortfolioMath`-ban van
    /// leírva — ott, ahol a widget is olvassa.
    var grandDepositsHUF: Decimal { PortfolioMath.depositsHUF(mathPayload) }

    /// Igaz, ha a belső átvezetések nem csengenek ki — vagyis hiányzik az
    /// egyik oldal kivonata. A felület ezt jelzi, mert a hiányzó fájl a
    /// platformonkénti számokat is pontatlanná teszi.
    var hasUnmatchedTransfers: Bool { unmatchedTransfers != nil }

    /// A ki nem csengő átvezetések összege és az érintett számlák NEVE.
    ///
    /// Korábban csak egy igen/nem volt, és a figyelmeztetés fixen a Revolut
    /// kivonatát kérte — akkor is, ha az eltérés máshonnan jött. Így nem
    /// lehetett megítélni, valós-e vagy maradvány. Most a szöveg megnevezi
    /// az összeget és a számlákat, tehát ellenőrizhető.
    var unmatchedTransfers: (netHUF: Decimal, accounts: [String])? {
        // Egy átvezetés párja csak akkor JÖHET MEG, ha a másik oldal
        // kivonatból származik. Ha annál a banknál a folyószámla már a
        // bankkapcsolatból érkezik, a pár SOHA nem fog megjelenni: a
        // bankkapcsolat egyenleget és kiadásokat ad, befizetés-tételeket nem.
        // Ilyenkor hallgatunk — a végösszeg amúgy is helyes, mert a párja
        // nélkül maradt átvezetést a számítás külső pénznek veszi.
        let linkedBanks = Set(bankLinkedPlatforms.values.compactMap {
            $0.split(separator: " ").first.map(String.init)   // „OTP Bank” → „OTP”
        })
        // A névtábla EGYSZER készül el. Korábban tételenként újraépült a
        // teljes platformlista — több száz befizetésnél ez képkockánként
        // több száz fölösleges kör volt.
        let names = Dictionary(resolvedPlatforms.map { ($0.id, $0.name) },
                               uniquingKeysWith: { first, _ in first })
        let internals = deposits.filter(\.isInternal).filter { entry in
            let name = names[entry.account] ?? entry.account
            return !linkedBanks.contains { name.localizedCaseInsensitiveContains($0) }
        }
        let net = internals.reduce(Decimal(0)) { $0 + $1.amountHUF }
        // 1 Ft alatti eltérés kerekítés, nem hiányzó kivonat.
        guard abs(net.doubleValue) > 1 else { return nil }
        let involved = Set(internals.map(\.account))
            .map { names[$0] ?? $0 }
            .sorted()
        return (net, involved)
    }

    /// Az ESZKÖZÖK értéke — a tartozások nélkül.
    ///
    /// A `grandTotalHUF` a NETTÓ vagyon (eszközök mínusz tartozások), és a
    /// fejlécben ez a helyes szám. A HOZAM viszont csak arra vonatkozhat,
    /// amit befektettél: egy hitelkártya-tartozás nem befektetési veszteség.
    /// Beleszámolva a hozam −44,66%-ot mutatott attól, hogy van kártyád.
    var assetsHUF: Decimal {
        resolvedPlatforms
            .filter(\.hasMeaningfulGain)
            .reduce(Decimal(0)) { $0 + valueHUF(ofPlatform: $1.id) }
    }

    /// Az összes tartozás, pozitív számként.
    var liabilitiesHUF: Decimal {
        -resolvedPlatforms
            .filter(\.isLiability)
            .reduce(Decimal(0)) { $0 + valueHUF(ofPlatform: $1.id) }
    }

    var grandGainHUF: Decimal { assetsHUF - grandDepositsHUF }

    var grandGainPct: Double {
        guard grandDepositsHUF > 0 else { return 0 }
        return (grandGainHUF / grandDepositsHUF).doubleValue * 100
    }

    // MARK: - Naptár és frissesség

    /// Kamat- és lejárati események egy helyen.
    var maturityCalendarEvents: [MaturityCalendarEvent] {
        let today = Calendar.current.startOfDay(for: Date())
        var events: [MaturityCalendarEvent] = []

        for platform in investablePlatforms {
            guard let year = platform.tbszYear,
                  let milestones = TBSZCalculator.milestones(collectionYear: year),
                  let deadline = TBSZCalculator.collectionYearEnd(year)
            else { continue }

            let title = "\(platform.name): gyűjtőév vége"
            events.append(MaturityCalendarEvent(
                kind: .collectionDeadline,
                platformID: platform.id,
                title: title,
                subtitle: "Lehetséges befizetés utolsó napja",
                date: deadline,
                daysFromToday: daysFromToday(deadline)
            ))
            events.append(MaturityCalendarEvent(
                kind: .threeYear,
                platformID: platform.id,
                title: "\(platform.name): 3 éves forduló",
                subtitle: "TBSZadózás a csökkentett sáv szerint",
                date: milestones.threeYear,
                daysFromToday: daysFromToday(milestones.threeYear)
            ))
            events.append(MaturityCalendarEvent(
                kind: .fiveYear,
                platformID: platform.id,
                title: "\(platform.name): 5 éves forduló",
                subtitle: "TBSZadózás adómentesen",
                date: milestones.fiveYear,
                daysFromToday: daysFromToday(milestones.fiveYear)
            ))
        }

        for asset in cashAssets {
            guard asset.netDailyRate != nil else { continue }
            let date = asset.asOf ?? today
            let rate = asset.netDailyRate?.doubleValue ?? 0
            events.append(MaturityCalendarEvent(
                kind: .savingsRate,
                platformID: asset.platform,
                title: "\(asset.name): becsült napi kamat",
                subtitle: String(format: "Nettó napi kamat %.2f%%", rate * 365 * 100),
                date: date,
                daysFromToday: daysFromToday(date)
            ))
        }

        return events.sorted { $0.date < $1.date }
    }

    /// Adatfrissességi nézet, hogy gyorsan lásd miért tűnik furcsának az érték.
    var dataFreshnessItems: [DataFreshnessItem] {
        var rows: [DataFreshnessItem] = []

        let refresh = lastRefresh
        let quoteState = freshnessState(from: refresh, good: 1, stale: 3, stale2: 7)
        rows.append(DataFreshnessItem(
            category: "Árfolyam és portfólió",
            title: "Portfólió frissítve",
            detail: refresh.map { "Utolsó mentett adat: \(Fmt.day($0))" } ?? "Még nem frissült",
            lastUpdated: refresh,
            state: quoteState
        ))

        if let fx = fxDate {
            let fxState = freshnessState(from: fx, good: 1, stale: 1, stale2: 2)
            rows.append(DataFreshnessItem(
                category: "Árfolyam",
                title: "EUR/HUF forrás",
                detail: "\(fxSource) — \(Fmt.time(fx))",
                lastUpdated: fx,
                state: fxState
            ))
        } else {
            rows.append(DataFreshnessItem(
                category: "Árfolyam",
                title: "EUR/HUF forrás",
                detail: "Még nem frissült az árfolyam.",
                lastUpdated: nil,
                state: .missing
            ))
        }

        if let oldest = oldestEstimateDays, oldest > 0, estimatedInterestHUF > 0 {
            let date = Calendar.current.date(byAdding: .day, value: -oldest, to: Date())
            let state = oldest >= 7 ? .outOfDate : (oldest >= 3 ? .stale : .good)
            rows.append(DataFreshnessItem(
                category: "Kamatbecslés",
                title: "Megtakarítás becslése öregedett",
                detail: "\(oldest) napja nem frissült kivonat",
                lastUpdated: date,
                state: state
            ))
        } else {
            rows.append(DataFreshnessItem(
                category: "Kamatbecslés",
                title: "Megtakarítás becslése",
                detail: "Friss kivonat alapján számított becslés",
                lastUpdated: nil,
                state: .missing
            ))
        }

        if hasMissingQuotes {
            let missing = platformSummaries.filter(\.isMissingValue).count
            let worst = missing > 0 ? .stale : .fresh
            rows.append(DataFreshnessItem(
                category: "Árak",
                title: "Hiányzó platformérték",
                detail: "\(missing) platformnál nincs teljesen friss árfolyam",
                lastUpdated: lastRefresh,
                state: worst
            ))
        }

        if let unmatched = unmatchedTransfers, abs(unmatched.netHUF.doubleValue) > 1 {
            rows.append(DataFreshnessItem(
                category: "Adatműveletek",
                title: "Belső átvezetés hiányzik",
                detail: "\(Fmt.huf(unmatched.netHUF)) (érintett: \(unmatched.accounts.joined(separator: \", \")))",
                lastUpdated: Date(),
                state: .good
            ))
        }

        return rows
    }

    private func daysFromToday(_ date: Date) -> Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
    }

    private func freshnessState(from date: Date?, good: Int, stale: Int, stale2: Int) -> FreshnessState {
        guard let date else { return .missing }
        let days = abs(Calendar.current.dateComponents([.day],
                                                      from: Calendar.current.startOfDay(for: date),
                                                      to: Calendar.current.startOfDay(for: Date())).day ?? 0)
        if days <= good { return .fresh }
        if days <= stale { return .good }
        if days <= stale2 { return .stale }
        return .outOfDate
    }
}

// MARK: - Napi / heti / havi

extension PortfolioStore {

    /// A mai érték platformonként — ez a periódusszámítás záró végpontja.
    /// A mai érték platformonként — a periódusszámítás záró végpontja.
    /// A TARTOZÁSOK kimaradnak: egy hitelkártya megjelenése nem havi
    /// veszteség, csak egy új kötelezettség.
    var todayByPlatform: [String: Decimal] {
        Dictionary(uniqueKeysWithValues:
            resolvedPlatforms.filter { !$0.isLiability }
                .map { ($0.id, valueHUF(ofPlatform: $0.id)) })
    }

    /// Napi, heti és havi eredmény. Csak azok az időszakok jönnek vissza,
    /// amikhez tényleg van korábbi mérés — becsült nyitóértéket nem gyártunk.
    var periodChanges: [Analytics.PeriodChange] {
        Analytics.periodChanges(snapshots: snapshots,
                                todayByPlatform: todayByPlatform,
                                deposits: deposits)
    }

    var todayChange: Analytics.PeriodChange? {
        periodChanges.first { $0.span == .day }
    }

    /// Csak az ÉRTÉKPAPÍR-vagyon forintban. A komponensek hatását ehhez mérjük,
    /// nem a teljes vagyonhoz: a megtakarítási számlát nem mozdítja meg az,
    /// hogy az NVIDIA esett.
    var securitiesValueHUF: Decimal {
        holdings.reduce(Decimal(0)) { $0 + (netValueHUF(for: $1) ?? 0) }
    }

    /// Az első olyan alap összetétele, amit ismerünk. Egyelőre egy alapod van;
    /// ha több lesz, ez lesz a hely, ahol ez kiderül.
    var knownComposition: FundComposition? {
        holdings.compactMap { FundComposition.known[$0.isin] }.first
    }
}
