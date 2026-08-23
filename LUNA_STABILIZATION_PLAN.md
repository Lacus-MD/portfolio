# LUNA végrehajtási terv — Portfólió 1.0 TestFlight stabilizálás

> Ez nem háttéranyag, hanem végrehajtási szerződés a LUNA modell számára.
> A munka megkezdése előtt olvasd végig a teljes fájlt. Minden munkamenet
> elején ellenőrizd az **Állapot** részt, és onnan folytasd, ahol az előző
> munkamenet megállt.

## 1. Küldetés

A Portfólió natív SwiftUI alkalmazás jelenlegi, funkciókban gazdag állapotából
készíts stabil, mérhető, adatbiztos és TestFlighton terjeszthető `1.0` Release
Candidate verziót.

Ez stabilizálási feladat, nem új termékfejlesztési ciklus. Új nagy funkciót ne
adj hozzá. A meglévő vizuális karaktert, navigációt és pénzügyi képességeket
őrizd meg, kivéve ahol a terv kifejezetten szerkezeti vagy akadálymentességi
javítást kér.

## 2. Kiindulási állapot

- Repo: `/Users/lacus/Portfolio`
- GitHub: `https://github.com/Lacus-MD/portfolio`
- Alkalmazáskód kiinduló commitja: `db2612e`
- Kiinduló build: `20`
- Marketingverzió: `1.0`
- Platform: iOS/iPadOS 26, SwiftUI
- Kiegészítők: Widget, Share Extension, watchOS app és watch widget
- Projektgenerátor: XcodeGen, igazságforrás: `project.yml`
- Fizikai iPhone devicectl ID:
  `F1C6000E-90D0-5D59-ABAC-232B64DE0DAF`
- Telefonos telepítő:
  `/Users/lacus/Portfolio/Telefonra telepítés.command`

A tervfájl létrehozása dokumentációs változás, ezért önmagában nem kap új
app-buildszámot. Az első alkalmazáskódot érintő mérföldkő a Build 21.

## 3. Állapot

Ezt a táblát minden mérföldkő végén frissítsd. Csak akkor jelölj egy buildet
elkészültnek, ha az összes elfogadási feltétele teljesült, a Release build
sikeres, a telefonos telepítés sikerült, és a commit felkerült GitHubra.

| Build | Munkacsomag | Állapot | Commit/tag |
|---|---|---|---|
| 21 | Tesztalapok, warningok, CI | nincs elkezdve | — |
| 22 | Pénzügyi számítások és importok | nincs elkezdve | — |
| 23 | Adatmentés, migráció, titkosítás | nincs elkezdve | — |
| 24 | Értesítések és háttérfrissítés | nincs elkezdve | — |
| 25 | Teljesítmény és görgetés | nincs elkezdve | — |
| 26 | Beállítások és akadálymentesség | nincs elkezdve | — |
| 27 | TestFlight Release Candidate | nincs elkezdve | — |

Engedélyezett állapotok:

- `nincs elkezdve`
- `folyamatban`
- `ellenőrzés alatt`
- `elkészült`
- `blokkolt: <konkrét ok>`

## 4. Kötelező munkafolyamat

### 4.1 Ág és verziókövetés

1. Ellenőrizd, hogy a munkakönyvtár tiszta, és ne írj felül ismeretlen
   felhasználói módosítást.
2. A munkát `stabilization/testflight-1.0` ágon végezd.
3. Minden logikai változtatás külön, áttekinthető commit legyen.
4. Egy munkacsomag végén emeld a `CURRENT_PROJECT_VERSION` értékét a tervben
   megadott buildre a `project.yml` fájlban.
5. Futtasd az XcodeGent, és commitold együtt a generált
   `Portfolio.xcodeproj/project.pbxproj` változását.
6. Minden sikeres mérföldkő kerüljön fel a távoli ágra.
7. Mérföldkő tag csak a telefonos ellenőrzés után készülhet:
   `build-21`, `build-22`, …, `build-27`.
8. A `main` ágba csak a Build 27 megfigyelési időszaka után olvaszd vissza.

### 4.2 Kötelező ellenőrzési sorrend

Minden appkódot érintő mérföldkő végén:

1. `git diff --check`
2. XcodeGen projektgenerálás
3. Unit tesztek
4. Releváns UI tesztek
5. Aláírt Release build
6. Buildszám ellenőrzése a kész `.app` Info.plistjében
7. Telepítés a fizikai iPhone-ra
8. Rövid kézi smoke teszt
9. Git commit és push
10. Állapottábla frissítése ebben a fájlban

A telefonos telepítő használata:

```zsh
./Telefonra\ telepítés.command
```

Ha az iPhone átmenetileg nem érhető el, a Release buildet befejezheted, de a
mérföldkövet nem jelölheted késznek és nem tageled, amíg a telepítés nem
sikerült.

### 4.3 Biztonsági korlátok

- Ne használj valódi banki kivonatot vagy személyes adatot tesztfixture-ként.
- Ne commitolj banki kulcsot, session ID-t, tokeneket vagy provisioning fájlt.
- A tesztek ne hívjanak élő banki, árfolyam-, hír- vagy iCloud-szolgáltatást.
- Pénzügyi hibát ne „javíts” tolerancia növelésével vagy teszt kikapcsolásával.
- UI teljesítményhibát ne rejts el animáció teljes eltávolításával, ha a
  felhasználói szándék az animáció megtartása.
- Meglévő mentési formátumot csak visszafelé kompatibilis migrációval változtass.
- Destruktív git vagy fájlrendszer-parancsot ne használj.

## 5. Jelenlegi ismert alapok

Már létezik:

- öt UI/performance teszt az `AppUITests/ScrollPerformanceTests.swift` fájlban;
- görgetési regresszióteszt mind a négy főfülhöz;
- külön portfóliógrafikon- és Beállítások-scroll mérés;
- callback weboldal tesztek az `EnableBankingCallbackSite/tests` mappában;
- közös `PortfolioMath`, amelyet az app és a widget is használ;
- főfájl, backup és titkosított backup helyreállítási útvonal;
- piaci és banki helyi értesítések;
- BGTask alapú háttérfrissítés.

Jelenleg hiányzik:

- iOS unit test target;
- automatikus iOS GitHub build/test workflow;
- importer fixture-k;
- migrációs és adatvesztési regressziótesztek;
- tesztelhető, tiszta értesítési szabálymotor;
- dokumentált teljesítménybaseline;
- teljes akadálymentességi ellenőrzés.

## 6. Build 21 — Tesztalapok, warningok és CI

### 6.1 Unit test target

A `project.yml` fájlban hozz létre `PortfolioTests` unit test targetet:

- típus: `bundle.unit-testing`;
- platform: iOS;
- deployment target: 26.0;
- forrás: `PortfolioTests`;
- dependency: `Portfolio`;
- modulhozzáférés: `@testable import Portfolio`.

Javasolt könyvtárstruktúra:

```text
PortfolioTests/
├── Support/
│   ├── FixtureLoader.swift
│   ├── DecimalAssertions.swift
│   └── TestFactories.swift
├── Fixtures/
│   ├── Broker/
│   ├── OTP/
│   ├── Revolut/
│   ├── StateTreasury/
│   └── Persistence/
├── PortfolioMathTests.swift
├── StatementImporterTests.swift
├── OTPImporterTests.swift
├── RevolutImporterTests.swift
├── StateTreasuryImporterTests.swift
├── PortfolioFileTests.swift
└── NotificationRuleTests.swift
```

A `DecimalAssertions` ne konvertálja automatikusan `Double`-re a pénzügyi
értékeket. Legyen egyértelmű, mikor várunk teljes egyenlőséget, és mikor
engedünk dokumentált kerekítési toleranciát.

### 6.2 Fordítási warningok

Javítsd legalább a jelenleg ismert helyeket:

- `AllocationPlannerView.swift`: elavult `onChange(of:perform:)`;
- `BankAuthWebView.swift`: elavult `NSURLErrorFailingURLStringErrorKey`;
- `DesignSystem.swift`: szükségtelen `nonisolated(unsafe)`;
- `PortfolioApp.swift`: eldobott `try? Inbox.store` eredmény;
- `PortfolioFile.swift`: értelmetlen opcionális downcastok.

Az Inbox-mentés hibáját kezeld vagy logold; ne csak nyomd el a warningot.

### 6.3 GitHub CI

Hozz létre iOS workflow-t, amely:

- ellenőrzi az elérhető Xcode-verziót;
- futtatja az XcodeGent;
- futtatja a unit teszteket;
- készít aláírás nélküli Debug buildet;
- futtatja a `git diff --check` ellenőrzést;
- nem használ banki vagy signing secretet.

Ha a GitHub hosted runner nem támogatja a szükséges Xcode/iOS SDK-t, ne
csökkentsd az app deployment targetjét. Dokumentáld a problémát, és használj
self-hosted Mac runt vagy kompatibilis, alacsonyabb szintű tesztlépést.

### 6.4 Elfogadási feltétel

- Unit test target parancssorból fut.
- Debug és Release build sikeres.
- Nincs Swift compiler warning.
- A GitHub minden pushnál ellenőriz.
- Build 21 települt a fizikai iPhone-ra.

### 6.5 Javasolt commitok

- `test: add iOS unit test foundation`
- `fix: eliminate compiler warnings`
- `ci: verify generated project and tests`
- `build: bump to 21`

## 7. Build 22 — Pénzügyi számítások és importok

### 7.1 PortfolioMath tesztmátrix

Teszteld:

- HUF, EUR és USD átváltás;
- nulla vagy hiányzó árfolyam;
- platformonként eltérő conversion spread;
- értékpapír, brókerkészpénz és megtakarítás összeadása;
- folyószámlák kizárása a befektetési hozamból;
- belső átvezetés ne legyen új külső befizetés;
- több platform közötti belső mozgás nettó kezelése;
- részben hiányzó quote;
- régi, platformbontás nélküli snapshot fallback;
- hitelkártya-tartozás negatív hatása a nettó vagyonra;
- folyószámla-változás ne jelenjen meg befektetési hozamként;
- widget és app ugyanabból a payloadból azonos összeget számoljon.

### 7.2 Importer fixture-ek

Készíts szintetikus fixture-eket ezekhez:

- `StatementImporter`
- `OTPImporter`
- `RevolutImporter`
- `StateTreasuryImporter`

Minden importer esetén legyen teszt:

- UTF-8 BOM;
- CRLF;
- üres sorok;
- vessző és pontosvessző delimiter;
- idézőjelben elválasztót tartalmazó mező;
- magyar és angol decimális formátum;
- negatív és pozitív előjel;
- hiányzó kötelező oszlop;
- ismeretlen tranzakciótípus;
- részben sérült sor;
- lokalizált dátum;
- időrendi sorrendtől eltérő bemenet.

Importer-specifikus esetek:

- OTP folyószámla és hitelkártya helyes megkülönböztetése;
- OTP-egyenleg ne legyen százalékos hozam;
- Revolut Savings kamat és normál folyószámla;
- Államkincstár befektetett és aktuális érték;
- bróker conversion díja ne kerüljön kétszer levonásra.

### 7.3 Idempotencia

Minden importer tesztelje ugyanazon fájl kétszeri importját. A második import
után ne változzon:

- a végső egyenleg;
- a tranzakciók száma;
- a befizetések összege;
- a díjak összege;
- a hozam;
- a snapshotok száma.

### 7.4 Elfogadási feltétel

- Minden pénzügyi és importer teszt determinisztikus.
- Dupla import nem készít duplikációt.
- OTP folyószámla mellett nem jelenhet meg hamis `+51,43%`.
- App és widget azonos nettó vagyont mutat.
- Build 22 települt a fizikai iPhone-ra.

### 7.5 Javasolt commitok

- `test: cover portfolio calculations`
- `test: add anonymized importer fixtures`
- `fix: make statement imports idempotent`
- `build: bump to 22`

## 8. Build 23 — Adatmentés, migráció és titkosítás

### 8.1 Tesztelhető tároló

A statikus `PortfolioFile` mögé vezess be tesztelhető tárolót injektálható:

- főfájl URL-lel;
- backup URL-lel;
- encrypted backup URL-lel;
- legacy URL-lel;
- `FileManager`-rel.

A jelenlegi statikus API maradjon façade, hogy a teljes appot ne kelljen
átírni és a widget továbbra is ugyanazt használja.

### 8.2 Payload round-trip

Minden mező kerüljön encode/decode round-trip tesztbe:

- holdings, snapshots, deposits, fees;
- platforms, cashAssets, cash;
- conversionSpread;
- tbszRules és scenario;
- constituentPrices és quantityTimeline;
- hiddenNews, expenses, creditCards, trades;
- themeID és allocationTargets;
- lastRefresh, fxRate, lastPrices;
- bankLinkedPlatforms és platformOrder.

### 8.3 Migráció

Készíts fixture-eket legalább ezekhez:

- régi lapos `cash` forma;
- régi egyetlen `conversionSpread`;
- hiányzó új mezők;
- platformbontás nélküli snapshot;
- ismeretlen vagy eltávolított theme ID;
- teljesen minimális korai payload.

Vezess be `schemaVersion` mezőt. Hiánya jelentse a legrégebbi támogatott
formátumot. A migráció legyen explicit és tesztelt; ne kizárólag véletlenszerű
`decodeIfPresent` fallbackekből álljon.

### 8.4 Helyreállítás

Teszteld:

- hiányzó főfájl;
- üres főfájl;
- sérült JSON;
- ép backup;
- sérült főfájl és sérült backup;
- legacy fájl költöztetése;
- üres állapot ne írja felül az ép backupot;
- sérült főfájl maradjon meg `portfolio.broken.json` néven;
- atomic write megszakítás utáni állapot.

### 8.5 Titkosított mentés

A `BackupSecurityManager` kulcstárolója legyen injektálható. Teszteld:

- encrypt/decrypt round-trip;
- hibás kulcs;
- módosított ciphertext;
- hiányzó Keychain-kulcs;
- régi titkosított mentés;
- helyreállítás titkosított backupból.

### 8.6 Elfogadási feltétel

- Egyetlen Payload-mező sem vész el újraindításkor.
- Build 20 mentése Build 23 alatt változatlanul betöltődik.
- Sérült főfájl esetén az ép backupból helyreáll.
- Hibás titkosítás nem eredményez üres állapot automatikus mentését.
- Build 23 települt a fizikai iPhone-ra.

### 8.7 Javasolt commitok

- `refactor: inject portfolio storage locations`
- `test: cover payload migration and recovery`
- `test: cover encrypted backup integrity`
- `build: bump to 23`

## 9. Build 24 — Értesítések és háttérfrissítés

### 9.1 Tiszta szabálymotor

Válaszd le a döntést a `UNUserNotificationCenter` mellékhatásairól. Javasolt
komponensek:

- `MarketAlertEvaluator`
- `BankMovementEvaluator`
- `NotificationDeduplicator`
- `NotificationScheduling` protokoll
- injektálható Clock
- injektálható key-value store

A tiszta evaluator adja vissza, milyen értesítéseket kellene elküldeni. A
rendszeradapter csak ezek ütemezéséért feleljen.

### 9.2 Piaci mozgás tesztek

- `+3%` és `-3%` pontosan küszöbérték.
- `±2,99%` nem küld.
- Azonos ISIN több számlán egyszer jelez.
- Emelkedés és esés külön irányként deduplikálódik.
- Régi cache-adat nem vált ki új eseményt.
- Maximum hat legnagyobb mozgás.
- Azonos napi azonos irány nem ismétlődik.
- Három napnál régebbi dedupe-adat kitakarítható.

### 9.3 Banki mozgás tesztek

- `+25 000 Ft` jóváírás.
- `-25 000 Ft` terhelés.
- Küszöb alatti összeg nem küld.
- Ugyanazon tranzakció új banki válaszban nem ismétlődik.
- Be- és kimenő tranzakció helyes címet és előjelet kap.
- Üres vagy különleges karakteres merchant.
- Maximum nyolc esemény.
- Hitelkártya-egyenleg nem lesz tranzakció.
- Belső átvezetés két oldala azonosítható és nem félrevezető.

### 9.4 Háttérkoordinátor

A BGTask munkát helyezd külön koordinátorba. Követelmények:

- success, error és cancellation esetén pontosan egyszer complete;
- expiration után ne mentsen félkész adatot;
- offline állapot ne törölje a korábbi árakat;
- részleges quote-válasz ne készítsen hamis snapshotot;
- a következő BGTask minden befejezési ágon újraütemeződik;
- Task cancellation továbbterjed a hálózati munkákba.

### 9.5 Fizikai megfigyelés

Legalább öt napon keresztül dokumentáld:

- feloldott és lezárt telefon;
- Wi-Fi és mobilinternet;
- Repülő mód;
- Background App Refresh kikapcsolva;
- értesítési engedély megtagadva, majd engedélyezve;
- app előtérben, háttérben és kilőve.

Az iOS nem garantálja a BGTask futtatását. A sikert ne az jelentse, hogy
„minden nap pontos időben futott”, hanem hogy amikor futási lehetőséget kapott,
helyesen és adatvesztés nélkül viselkedett.

### 9.6 Elfogadási feltétel

- Nincs duplikált vagy hamis esemény.
- Offline frissítés nem rontja el a portfóliót.
- Cancellation után nincs félkész mentés.
- A valós megfigyelési napló bekerült a repo dokumentációjába.
- Build 24 települt a fizikai iPhone-ra.

### 9.7 Javasolt commitok

- `refactor: extract notification rule engine`
- `test: cover market and banking alerts`
- `fix: complete background refresh safely`
- `docs: record background refresh observations`
- `build: bump to 24`

## 10. Build 25 — Teljesítmény és görgetés

### 10.1 Baseline

A meglévő `AppUITests/ScrollPerformanceTests.swift` teszteket először változtatás
nélkül futtasd, és mentsd a baseline mérőszámokat. Ne optimalizálj mérés nélkül.

### 10.2 Mérendő folyamatok

- Portfólió első megjelenése.
- Vagyon-grafikon első kirajzolása.
- Grafikon pontok helyzete és clippingje.
- Hírek loading animációja és az azt követő fade.
- Kiadások hosszú listája.
- Beállítások és témagaléria.
- Világos/sötét váltás.
- Háttérből visszatérés.
- Widget-adat mentése.

### 10.3 Eszközök és javítási irányok

- Instruments Time Profiler.
- SwiftUI instrument.
- `os_signpost` a refresh, import, chart preprocessing és news load köré.
- Főszálon futó fájl-, XML-, JSON- és képfeldolgozás azonosítása.
- Ismételt apró `@Observable` módosítás helyett kötegelt frissítés.
- Chart pontok és path előfeldolgozása háttérben.
- Hírképek lemondható előtöltése.
- Görgetés közbeni blur, shadow és gradient költségének mérése.

Ne távolítsd el a hírek loading animációját: a követelmény az, hogy a loading
megmaradjon, majd az elkészült szöveg finoman fade-eljen be.

### 10.4 Teljesítménykeret

- Ne legyen reprodukálható, 100 ms feletti user-visible hitch.
- A baseline scroll metric legfeljebb 10%-kal romolhat.
- A hírek animációja betöltés közben is folyamatos.
- Témaváltás ne építse újra szükségtelenül a teljes appfát.
- A portfóliógrafikon pontjai ne lógjanak le és ne mozduljanak el.

### 10.5 Elfogadási feltétel

- Minden meglévő és új performance teszt zöld.
- Instruments mérés dokumentálva előtte/utána.
- Négy főfülön nincs kézzel reprodukálható akadás.
- Build 25 települt a fizikai iPhone-ra.

### 10.6 Javasolt commitok

- `perf: add signposts and baseline metrics`
- `perf: move preprocessing off main actor`
- `test: expand scroll regression coverage`
- `docs: record performance comparison`
- `build: bump to 25`

## 11. Build 26 — Beállítások és akadálymentesség

### 11.1 Beállítások szerkezete

A hosszú Beállítások listát bontsd navigációs célokra:

- Megjelenés és témák
- Bankkapcsolatok és import
- Értesítések
- Adatok és biztonsági mentés
- Számlák és platformok
- Névjegy és jogi dokumentumok

A fejlesztői eszközök Release konfigurációban ne jelenjenek meg.

### 11.2 Témagaléria

- Csoportok: Pasztell, Élénk, Monokróm.
- Egyszerre csak az aktív világos vagy sötét variáns látszódjon.
- Rendszer módban a készülék aktuális megjelenését kövesse.
- Mind az öt monokróm téma pontosan egy színes akcentust tartalmazzon;
  minden más témaszín legyen szürkeárnyalatos.
- A kiválasztott téma ne csak színnel legyen jelölve.
- Mind a 17 téma kerüljön kontrasztellenőrzésre.

### 11.3 Akadálymentesség

Ellenőrizd és javítsd:

- VoiceOver címkék;
- VoiceOver bejárási sorrend;
- gombok és grafikonok értelmes accessibility value-ja;
- Dynamic Type legnagyobb méretig;
- 320–402 pt iPhone-szélesség;
- iPad korlátozott tartalomszélessége;
- Reduce Motion;
- Increase Contrast;
- minimum 44×44 pt interaktív célterület;
- nyereség, veszteség és tartozás ne csak színnel legyen közölve.

### 11.4 Elfogadási feltétel

- Nincs levágott számlanév vagy összeg.
- VoiceOverrel minden főfunkció elérhető.
- Legnagyobb Dynamic Type mellett nincs használhatatlan képernyő.
- A monokróm témákban is megkülönböztethetők az állapotok.
- Build 26 települt a fizikai iPhone-ra.

### 11.5 Javasolt commitok

- `refactor: split settings into destinations`
- `a11y: support voiceover and dynamic type`
- `test: cover theme contrast and accessibility`
- `build: bump to 26`

## 12. Build 27 — TestFlight Release Candidate

### 12.1 Automatikus ellenőrzés

- Minden unit test.
- Minden UI test.
- Release build.
- Widget target build.
- Share Extension target build.
- watchOS és watch widget target build.
- `git diff --check`.
- Tiszta munkakönyvtár.

### 12.2 Frissítési és állapotmátrix

Kézzel teszteld:

- tiszta telepítés;
- frissítés Build 20-ról;
- frissítés a legutóbbi stabil buildről;
- üres portfólió;
- csak banki számla;
- csak TBSZ;
- több száz tranzakció;
- offline indulás;
- lejárt banki hozzájárulás;
- megtagadott értesítési engedély;
- sérült főfájl és ép backup;
- zárolt telefon utáni első indítás;
- widget friss és elavult adatokkal.

### 12.3 Release folyamat

1. Build 27 telepítése a fizikai iPhone-ra.
2. 5–7 nap napi valós használat.
3. A megfigyelési időszakban csak kritikus vagy adatbiztonsági hibák javítása.
4. Ha új build kell, növeld a buildszámot; ne tölts fel ugyanazzal a számmal.
5. Készíts `release/1.0` taget.
6. Olvaszd vissza a stabilizációs ágat `main` ágba.
7. Push GitHubra.
8. Készíts Archive-ot és töltsd fel App Store Connectre.
9. Add belső TestFlight csoporthoz.
10. Készíts rövid release notes és ismert korlátozások dokumentumot.

### 12.4 Elfogadási feltétel

- Legalább öt nap kritikus hiba nélküli napi használat.
- Nincs ismert adatvesztési útvonal.
- Nincs hamis pénzügyi százalék vagy duplikált import.
- Nincs reprodukálható görgetési akadás.
- A TestFlight build telepíthető és elindul.

## 13. Végső Definition of Done

A teljes küldetés csak akkor kész, ha:

- minden unit és UI teszt zöld;
- nincs compiler warning;
- nincs adatvesztés migrációnál vagy sérült főfájlnál;
- nincs ismételt importból duplikáció;
- nincs hamis banki vagy piaci értesítés;
- nincs reprodukálható scroll hitch;
- mind a 17 téma működik világos és sötét módban;
- VoiceOver és Dynamic Type használható;
- a végső build fizikailag települt az iPhone-ra;
- a stabilizációs ág és a `main` tiszta, minden commit felkerült GitHubra;
- az App Store Connect/TestFlight feltöltés sikeres;
- a Release Candidate legalább öt napig kritikus hiba nélkül futott.

## 14. Munkamenet végi jelentés formátuma

Minden LUNA-munkamenet végén hagyj rövid, tényszerű jelentést:

```text
Aktuális build:
Állapot:
Elkészült:
Módosított fájlok:
Lefuttatott tesztek:
Telefonos telepítés:
Commit/push:
Nyitott hibák vagy blokkolók:
Következő konkrét lépés:
```

Ne jelents „kész” állapotot pusztán azért, mert a kód lefordul. A megfelelő
teszt, fizikai telepítés, GitHub push és a fenti elfogadási feltételek együtt
jelentik a kész állapotot.
