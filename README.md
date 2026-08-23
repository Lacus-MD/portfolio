# Portfólió

## Felépítés (2026-08-21 redizájn után)

```
App/          iPhone + iPad app — három képernyő (Home / Compare / Detail)
Watch/        watchOS app + Smart Stack widgetek
Widgets/      iPhone widgetek (kezdőképernyő + zárolási képernyő)
Share/        megosztólap-célpont (kivonat átvétele)
Shared/       modellek, hálózat, elemzés, dizájnrendszer — minden cél ezt használja
```

A **platform** a szervező egység: minden pozíció, befizetés, díj, készpénz és
árrés egy platformhoz tartozik. Kétféle platform van — `brokerage`
(értékpapírszámla) és `savings` (kamatozó készpénz, pl. Revolut Savings).
Ez utóbbi azért kellett, mert egy megtakarítási egyenlegnek **nincs ISIN-je,
darabszáma és árfolyama** — a régi modell csak pozíciót ismert.

## Dizájn

A pasztell redizájn (`Shared/Design/DesignSystem.swift`) a
`design_handoff_pastel_portfolio` handoffot követi: krém/szilva/korall paletta,
Poppins tipográfia, 36-os kártyasugár, odométeres összegek.

**Poppins**: ha a betűkészlet nincs beágyazva, a rendszer futásidőben az
SF `rounded` változatára esik vissza — ez áll hozzá legközelebb súlyban.
A beágyazás bármikor pótolható, kódmódosítás nélkül.

## Óra

Az óra **külön eszköz**, nem éri el az App Group konténert. Ezért a telefon
`WCSession.updateApplicationContext`-tel küld egy kis összefoglalót
(`Shared/WatchSummary.swift`). Miért `applicationContext` és nem üzenet:
mindig a LEGFRISSEBB állapotot tartja, felülírja az előzőt, és akkor is
kézbesít, ha az óra épp nem elérhető. Egy vagyonkijelzőnek pontosan ez kell.

Az óra **nem számol és nem kér le árfolyamot** — a watchOS-en a hálózat drága.
A kapott számokat tárolja, offline is mutatja, és kiírja, mennyire friss.

Mini iPhone app egyetlen feladattal: a Lightyear/TBSZ-portfólió értékének követése
forintban és euróban.

## Adatforrások — mind ellenőrizve 2026-08-20-án

| Adat | Forrás | Megjegyzés |
|---|---|---|
| ETF árfolyam | `api.boerse-frankfurt.de` quote_box, **ISIN alapján**, Xetra | Kulcs nélkül. Mind a 7 vizsgált Vanguard UCITS ETF-re adott friss árat. |
| EUR/HUF | `api.frankfurter.dev` (ECB napi referencia) | HTTPS, kulcs nélkül. Idősort is ad. |
| Árfolyam-tartalék | Yahoo `v8/finance/chart`, ticker alapján | Gyakran 429-el (rate limit). Csak tartalék. |

### Amit szándékosan NEM használunk

- **MNB SOAP** — adóügyileg ez a mérvadó jegyzés, de csak `http://`-n él
  (a HTTPS 404), az iOS ATS pedig tiltja. Az eltérés az ECB-től 0,02%
  (365,03 vs 365,10), ami értékkövetéshez jelentéktelen — nem ér meg egy
  ATS-kivételt.
- **Börse Frankfurt `price_history`** — üres `{}`-t ad aláíró fejléc nélkül.
- **Stooq, justETF** — halott, illetve 502.
- **Vanguard „hivatalos API"** — nincs; a `vanguardinvestor.co.uk` Angular
  HTML-vázat ad vissza, nem adatot.

## A görbe

A történeti görbét az app **maga építi** napi pillanatképekből, nem külső
történeti API-ból. Oka kettős: a megbízható történeti végpontok hiánya, és
hogy a portfólió alakulása nem azonos az ETF árfolyamával — a befizetések
megtörik a görbét.

A menüben lévő „Görbe visszatöltése" a **mai összetétellel visszaszámolt**
görbét tölti le a Yahoo-ról. Ez nem a tényleges múltbeli vagyonod, hanem az,
hogy „mennyit érne a mostani portfólióm, ha végig ez lett volna". A
visszaszámolt sorok `isBackfilled` jelzést kapnak, hogy az élő mérésektől
elkülönüljenek.

## Amit az app szándékosan nem csinál

- **Nem mutat adókulcsot.** A TBSZ-nél csak a 3 és 5 éves fordulónapot
  számolja ki dátumként. Az adómérték jogszabálytól függ és változik — azt a
  NAV-nál vagy a számlavezetőnél kell megnézni.
- **Nem kereskedik, nem ad tanácsot.** Csak megjeleníti, ami van.
- **Nem kér be Lightyear-jelszót.** Nincs is mihez: a Lightyearnek nincs
  nyilvános API-ja, a pozíciók kézi bevitelűek.

## Tárolás és adatbiztonság

**A Swift szintetizált `Decodable`-je NEM használja a property alapértékét
hiányzó kulcsnál — `keyNotFound` hibát dob.** Ez itt valódi adatvesztést
okozott: valahányszor a modell új, nem opcionális mezőt kapott (`account`,
`cash`, `deposits`, `fees`), a már lementett állomány dekódolhatatlanná vált,
a betöltés üreset adott vissza, és a rákövetkező mentés felülírta a jó adatot.

Ezért **minden modell kézzel írt `init(from:)`-t használ**, ami a később
hozzávett mezőket `decodeIfPresent`-tel olvassa. Új mező hozzáadásakor ezt
bővíteni kell — különben a hiba visszatér.

Három réteg védi az adatot:

1. **Toleráns dekódolás** — a régi állomány betöltődik és migrálódik.
2. **Biztonsági másolat** (`portfolio.backup.json`) — minden sikeres, nem üres
   mentésnél frissül. Sérülésnél ebből áll vissza, a sérült fájlt pedig
   `portfolio.broken.json` néven félretesszük, nem dobjuk el.
3. **Nem írunk olyan fájlra, amit nem sikerült elolvasni.** Ha a fájl létezik,
   de sem ő, sem a másolat nem dekódolható, az app *egyáltalán nem ment*, és
   ezt ki is írja. Inkább ne működjön, mint hogy véglegesen felülírja.

Emellett a betöltés a `PortfolioStore.init()`-ben történik, nem `.task`-ban:
két párhuzamos `.task` sorrendje nem garantált, és a vesztes esetben a
`refresh()` üres állapottal futott le, majd elmentette azt.

A widget írás előtt **frissen újraolvas**, mert a hálózati hívások alatt az app
is írhatott — a régi másolat visszaírása eldobná az időközbeni importot.

## Tárolás

Egyetlen JSON az app Application Support mappájában (`portfolio.json`),
atomi írással. Nincs SwiftData, nincs séma-migráció — három pozícióhoz
felesleges kockázat lenne.

## Miért egyeznek a számok a Lightyearrel

A fő szám (`netValueHUF`) szándékosan **nem** a nyers piaci érték, hanem az,
amit visszaváltáskor ténylegesen kapnál:

```
netValueHUF = darab × ár × EUR/HUF × (1 − átváltási_árrés) + készpénz
Kezdetektől = netValueHUF − összes_befizetés
```

Három mérés vezetett ide, mindegyik a tulajdonos valódi kivonatán:

1. **Az átváltási árrés a kivonatból jön, nem beégetett szám.** A forintból
   kimenő átváltások díjhányada — a mérésben 0,3498%. Ezzel csökkentve a
   középárfolyamos érték **hat forinton belül** egyezett a Lightyear kijelzésével.
   Új import újraszámolja, tehát nem rohad meg, ha a bróker árat változtat.
2. **A készpénz kivezethető a kivonatból**, de csak a helyes előjel-logikával —
   ezt mértük, nem feltételeztük: `Deposit` (Net==Gross, a díj nem terheli a
   számlát), `Conversion` (a díj már a Gross-ban), `Buy` (Gross = ár + díj),
   `Sell`/`Dividend` (Net). Így jött ki 608,60 Ft + 0,02 USD — pont amit a
   Lightyear mutat.
3. **A hozam alapja a befizetés, nem a bekerülési ár.** A bróker mércéje:
   „betettem ennyit, most ennyim van". A díjak automatikusan veszteségként
   szerepelnek, mert csökkentik a mai értéket.

A pozíciósorok is árréssel számolnak, hogy az összegük kiadja a fejlécet.

**Devizaforrás:** elsődlegesen napra kész piaci jegyzés, tartalék az ECB. Az
ECB délután publikál, tehát délelőtt a „legfrissebb" ECB-adat még a tegnapi —
ez fél százalékos eltérést okozott. A lábléc ezért kiírja az árfolyam
**dátumát és forrását** is.

## A részletek és az összevetés EGY görgethető oszlop

A handoff a 3b/3c képernyőn rögzített alsó lapot ír elő — ott pár sor volt benne.
Azóta idekerült az eszközlista, az alap-összetétel gyűrűje, a TBSZ feltörés-
kalkulátor és a díjbontás. **Fix panelként ez nem görgethető és tömör:** a
tartalom egyszerűen kifutott a képernyőből, és a felhasználó nem fért hozzá.

Ezért a lap-rész most a fő görgetés VÉGÉN folytatódik, megtartva a lekerekített
tetejét. A húzható fogantyú kikerült — húzható lapot ígért, ami már nem az.

Ugyanez az összevetés nézetnél: a jelmagyarázat több platformmal hosszabb lehet,
mint amennyi egy fix panelbe fér.

## Felépítés: négy fül

Natív `TabView` — iOS 26-on magától Liquid Glass anyagot kap, nem kell utánozni.
**Portfólió · Hírek · Platformok · Beállítások.** Ez váltotta ki a fejléc fehér
menügombját és az alsó „összevetés" gombot: mindkettő egy-egy HELY volt, nem
művelet, tehát fülként a helyük.

A fejlécben az app saját jele áll. Korábban egy monogramos „profilkép" volt
(a handoffból örökölve) — egy EGYFELHASZNÁLÓS appban ez semmit nem jelent,
nincs kitől megkülönböztetni a tulajdonost.

## Sötét mód

Szemantikus, rendszertémához igazodó színek (`DS.Color.canvas` / `.card` /
`.ink`), dinamikus `UIColor`-ral — így minden nézet magától követi a rendszert,
nem kell a témát kézzel átfűzni. Az AKCENTUSOK (korall/menta/lila) mindkét
módban ugyanazok: azok az identitás.

Az ikonnak három változata van (világos / sötét / színezett) az eszközkatalógus
`appearances` kulcsával.

watchOS-en nincs dinamikus `UIColor` és minden sötét — ott a sötét változat a
helyes, nem a világos.

## Színtémák

Négy paletta (`Shared/Design/AppTheme.swift`), mindegyik világos ÉS sötét
változattal: **Pasztell · Tenger · Erdő · Grafit**. A nézetek SZEREPEKET kérnek
(vászon, kártya, szöveg, héj, három akcentus), nem konkrét színeket — így egy
új téma felvétele egyetlen struktúra kitöltése.

A három akcentus mindig **egy meleg, egy hűvös és egy köztes**, hasonló
világossággal: így a platformkártyák egymás mellett kiegyensúlyozottak
maradnak, és a szín nem rangsorol.

A `DS.Color` globális, ezért témaváltáskor a fa `.id(themeID)`-re kötve épül
újra — egy beállítás-váltásnál ez elfogadható ár.

## Import-automatizálás (1–2. szint, megépült)

A havi kör mostantól: **letöltöd a kivonatot a Macen — kész.** A többi magától
megy. A lánc, minden eleme mérve:

1. **Mac letöltés-figyelő** (`Tools/statement-watcher.sh` + launchd agent):
   a Letöltésekből a kivonat-mintájú fájlokat átteszi az iCloud „Portfólió"
   mappába. Idegen fájlhoz nem nyúl (mérve: a nem-kivonat CSV a helyén maradt).
   **TCC-tanulság:** a launchd-ből futó zsh a védett Letöltéseket NÉMÁN üresnek
   látja — mérve: 1 elem a valódi 267 helyett, hibaüzenet nélkül. Ezért a
   scriptet egy `osacompile`-lal fordított kis app (`PortfolioFigyelo.app`)
   futtatja: egy app tud engedélyt kérni, és a rendszer megjegyzi.
   Eltávolítás: `launchctl unload ~/Library/LaunchAgents/hu.halasz.portfolio.statement-watcher.plist`
2. **Az app minden előtérbe kerüléskor feldolgoz** (`scenePhase`). Korábban
   csak hidegindításkor — ha az app a háttérben futt, a megosztott fájl
   elveszettnek látszott.
3. **Élő iCloud-figyelés** (`NSMetadataQuery`): amíg az app nyitva van, a
   Macről érkező fájl magától beolvasódik.
4. **Figyelt mappák**: a Beállításokban kijelölhetsz mappákat (akár az iCloud
   Drive gyökerét) — biztonsági könyvjelzővel tárolódnak, és minden
   megnyitáskor átnézzük őket. CSAK a felismerhető kivonat-nevekhez nyúlunk,
   és a fájlok a helyükön maradnak (jegyzék: név+méret+módosítás).
5. **„Megnyitás — Portfólió"** a Fájlokból/Mailből (CFBundleDocumentTypes,
   Alternate rank — nem vesszük el a PDF-eket a rendszertől).
6. **App Intents**: „Portfólió frissítése" és „Kivonat beolvasása" a
   Parancsok appból.
7. **BGAppRefresh** naponta — de az iOS a futtatást nem garantálja, ez
   kényelmi réteg, nem ígéret.

**A feldolgozott fájl nem törlődik többé**: a „Portfólió/Feldolgozva"
almappába kerül. A figyelővel együtt a törlés azt jelentette volna, hogy a
kivonat eredetije eltűnik — egy bankkivonat archívum-érték.

A 3. szint (Enable Banking PSD2) tudatosan nincs megépítve — a döntés és a
kutatás a `Docs/import-automatizalas-terv.md`-ben.

## Költés-elemzés: fix vs. változó, futamidő, előfizetések

`SpendingAnalysis` — a beolvasott tételekből, feltevés nélkül.

**Fix vs. változó.** Fix a törlesztés, a rezsi, a biztosítás, az előfizetés és
a banki díj: ezek akkor is elmennek, ha egy hónapig ki sem lépsz a lakásból.
A tulajdonos három hónapján mérve a fix rész 849k → 962k → 1041k, miközben a
bevétel nem nőtt. A bontás ellenőrizhető: a három hónap egyenlege −213 ezer,
a folyószámla pedig 507 428 → 289 534, azaz −218 ezer.

**Futamidő.** Nettó vagyon ÷ havi fix költség, mellette KÜLÖN kiírva, mennyi
ebből azonnal elérhető — a TBSZ eladása idő és adó, egy vészhelyzetben nem
ugyanaz, mint a folyószámlán álló pénz.

**Ismétlődő terhelések.** A naiv szabály (ugyanaz a kereskedő több hónapban)
a Lidlt és a benzinkutat is előfizetésnek nézte — mérve, a találatok fele
bevásárlás volt. Az előfizetést az különbözteti meg, hogy az ÖSSZEG is
állandó: ezért havonta legfeljebb egy terhelést fogadunk el, és a szórásra is
szűrünk (≤8%). Így 7 valódi találat maradt, 939 800 Ft/év.

## Hitelkártya fizetési emlékeztető

A kivonatból eddig is kiolvastuk a határidőt és a minimum fizetendőt, csak
nem kezdtünk velük semmit. Most helyi értesítés megy **három nappal előtte,
reggel 9-kor** — nem a határidő napján, mert akkor egy átutalás elindítására
már késő. Külön kapcsolóval, és az engedélyt CSAK a bekapcsoláskor kérjük:
indításkor engedélyt kérni azelőtt, hogy tudnád, mire jó, udvariatlan.

Lejárt határidőre nem időzítünk: az nem sürgős, hanem elavult — új kivonat kell.

## Kézi átsorolás

A `manualCategory` mező eddig is a modellben volt, felület nem tartozott
hozzá. Most koppintásra átsorolható bármelyik tétel, és a jelölés miatt a
következő kivonat-beolvasás NEM írja felül — enélkül a javítás értelmetlen
lenne, mert a szabály visszatenné.

## Az iCloud-mappa, ami nem jelent meg

Három oka volt, mind javítva:

1. **Üres mappát az iOS nem mutat** a Fájlok appban. A könyvtár létrejött, de
   üresen maradt. Most egy rövid útmutató-fájl kerül bele.
2. **Az `NSUbiquitousContainers` beállítást az iOS gyorsítótárazza**, és csak
   akkor olvassa újra, ha a build-szám nőtt. Az sosem változott (1 → 2).
3. **A mappa csak CSV-t vett át.** A kivonatok ma már PDF-ben jönnek, tehát a
   bedobott fájl csendben ottmaradt. Most PDF/TXT/XML is.

## OTP-kivonat és a Kiadások fül

`OTPImporter` — kétféle elrendezés, ezért két elemző. A bankszámlán a tétel
KÉT sor (dátumok + összeg, majd a megnevezés), a hitelkártyán EGY (az összeg
a sor végén). Az összegek forintosak, ezres ponttal, tizedes nélkül.

**A beolvasás önmagát ellenőrzi.** A kivonat kiírja a saját összesítését, és
ha a beolvasott tételekből nem jön ki ugyanaz, azt jelezzük. Négy valódi
kivonaton mérve, forintra egyező:

| kivonat | tétel | jóváírás | terhelés | nyitó+forgalom = záró |
|---|---|---|---|---|
| június | 138 | ✓ | ✓ | ✓ |
| július | 132 | ✓ | ✓ | ✓ |
| augusztus | 126 | ✓ | ✓ | ✓ |
| hitelkártya | 11 | ✓ | ✓ | ✓ |

### Kategorizálás

`ExpenseCategorizer` — szabályalapú, nem tanuló. Egy pénzügyi appban a
kiszámíthatóság többet ér: ugyanaz a bolt mindig ugyanoda kerül, és ha téved,
a szabály javítható. Valós adaton mérve: **a pénz 97,3%-a besorolva**, a
maradék „Egyéb" — nem tippelünk.

**Nem minden kimenő forint kiadás.** A Lightyearbe, Revolutba vagy
állampapírba átvezetett pénz a saját számládra megy; költésként számolva
ugyanaz a forint kétszer szerepelne, és a havi kiadás 1,2 millióval tűnne
nagyobbnak. Ezek külön szekcióban állnak (`isSpending == false`).

A kereskedőnév kinyerésénél a devizajelölő mező (`25EUR`) pont három betűs,
ezért átcsúszott a „legalább három betű" szűrőn — három tétel kereskedője
`25EUR` lett a valódi `WHOOP` helyett. Mérve, javítva.

### A hitelkártya kötelezettség, nem eszköz

Új platformtípus (`Platform.Kind.credit`). A tartozás **csökkenti a nettó
vagyont** — ez a fejlécben helyes —, de **kimarad a hozamból**: egy
hitelkártya nem befektetési veszteség. Beleszámolva a hozam −44,66%-ot
mutatott attól, hogy van kártyád.

A típust az import mindig HELYESBÍTI (a nevet és a színt nem): ha egy kártya
korábban megtakarításként került be, az számítási hiba, nem ízlés kérdése.

A folyószámla befizetései a VALÓDI tételekből képződnek, mindegyik a saját
napjával — nem egyetlen összegként a kivonat dátumára. Az utóbbi fantom
pénzbeáramlást csinált: a havi eredmény −32%-ot mutatott attól, hogy a számla
bekerült.

## Banki kivonat PDF-ből

A lakossági OTP (és több más bank) **PDF-ben** adja a kivonatot; a CSV/Excel
és az MT940/CAMT export a vállalati csatornákon (Electra, eBIZ) van — a bank
saját súgójában a lakossági letöltésnél csak PDF szerepel.

Ezért az import PDF-et is fogad: a `PDFStatement` a PDFKit-tel kiolvassa a
szövegréteget, és onnantól ugyanaz a dolgunk, mint egy CSV-nél — a formátumot
a TARTALOM dönti el, nem a kiterjesztés. Mérve egy valódi, generált PDF-en:
7 625 karakter, 107 sor.

Szkennelt kivonatnál nincs szövegréteg. Ezt kimondjuk (`noTextLayer`), nem
próbálunk félig üres eredményt beolvasni.

**A fájl nem megy sehova**: a kinyerés az eszközön történik, ahogy a
CSV-beolvasás is.

## Egy matek, két felület

`Shared/Services/PortfolioMath.swift` — a portfólió számításai EGY helyen, a
tárolt állományból. A tár és a widget is ezt hívja.

**Miért kellett:** a widget saját, párhuzamos matekot futtatott — csak az
értékpapírokból, euróban, a BEKERÜLÉSI ÁRHOZ mérve. Az app közben
platformonként, forintban, a BEFIZETÉSEKHEZ mérve számolt. Ugyanaz a
portfólió két felületen két különböző igazságot mutatott: a widgeten egy
tétel „VWCE 100%"-on, más alakú görbével. Ez nem elírás volt, hanem
szerkezeti hiba.

Három következménye volt, mind javítva:

1. **A widget egy tételt mutatott.** Most a platformokat sorolja, forintos
   súllyal — ugyanaz a három, mint az appban.
2. **A görbe más volt.** A szikragörbe az értékpapírok eurós értékét rajzolta;
   most a napi ÖSSZVAGYON forintban, ugyanabból a sorozatból, mint a
   kezdőképernyő közös görbéje.
3. **A widget rontotta az app görbéjét.** Amikor frissült, felülírta a napi
   mérést PLATFORMBONTÁS NÉLKÜL — így a kezdőképernyő közös görbéjéről aznapra
   eltűntek a vonalak, pont azokon a napokon, amikor nem nyitottad meg az
   appot. Most a bontást is menti.

A widget befizetés-összege ráadásul nyersen adta össze a tételeket, a belső
átvezetéseket is beleértve — ugyanaz a hiba, amit az appban már javítottunk
(+55%-os álhozam). Most közös a szabály.

## A tárolt állomány dekódolója: három mező kimaradt

`lastRefresh`, `fxRate` és `lastPrices` mentve volt, de a kézzel írt
`init(from:)` sosem olvasta vissza. Következmény: az utolsó ismert árak és
árfolyam MINDEN indításnál elvesztek — az app hálózat nélkül nem tudott
értéket mutatni, a widget pedig egyáltalán nem tudott a mentett árakra
visszaesni, tehát mindig „nincs friss adat" állapotba került.

Mérve: a tárolt JSON-ban ott volt `IE00BK5BQT80: 166.32`, a betöltött
szerkezetben nem. A javítás után a közös matek a valódi állományon
1 159 498 Ft-ot és három platformot ad — ugyanazt, amit a képernyő.

**Tanulság:** kézzel írt dekódolónál a mezőlistát ellenőrizni kell, nem
elhinni. Egy kimaradt mező nem fordítási hiba, csak csendben nulla lesz.

## Olvashatóság: chipek, nevek, hiányzó szakaszok

Három hiba, ami csak VILÁGOS módban és csak a kezdőképernyőn látszott:

- **Az üveggombok szövege eltűnt.** A `RangeChips` fixen `onShell()`-t
  használt, ami sötét héjon fehér — a kezdőképernyő viszont a VÁSZNON ül, és
  ott a fehér szöveg világos módban láthatatlan. A hívó most megadja a
  tintát; a részletnézet (héjon ül) továbbra is `onShell()`-t ad.
  Ugyanaz a hibacsalád, mint a világos navigációs sáv volt.
- **A jelmagyarázat kódokat mutatott** (`T2`, `RS`, `RF`), mert a teljes nevek
  nem fértek egy sorba. A monogram viszont kód, amit a felhasználónak fejben
  kellene feloldania a saját appjában. `FlowLayout` (soronként tördel), és
  kiírjuk a neveket. A dátumsáv kiolvasása is nevet mutat.
- **A ritkábban mért vonal értéke hol megjelent, hol nem** a dátumsávban.
  Rögzített 6%-os távolság volt a feltétel; most a vonal SAJÁT szakaszán
  belül mindig kiírjuk (a görbe ott is folytonos vonalat rajzol, tehát a
  kiolvasás sem hiányozhat), a szakaszon kívül pedig nem találunk ki semmit.

Ha egy platform görbéje később kezdődik, mint a választott időszak, azt a
görbe alatt kimondjuk — a javítás **más a kétféle számlánál**: az
értékpapír-számláé visszaszámolható a napi árfolyamokból, a készpénzszámláé
viszont csak kivonatból jöhet. Egy közös mondat az egyiket félrevezetné.

## A Platformok fül kivezetve

2026-08-22-én kikerült: minden, amit mutatott, a kezdőképernyőn is megvan.
A kivezetés előtt átvezetve, mert három dolog tényleg csak ott volt:

| Ami ott volt | Hova került |
|---|---|
| időbontás (7N / 30N / 3H / MAX) | a közös görbe alá |
| 100-ra indexált összevetés | `Ft` ⇄ `index` kapcsoló ugyanott |
| platformonkénti aktuális érték | a platformkártyára, a név alá |
| összes befizetés | a fejlécbe, az egyenleg alá |
| a görbe időtengelye (kezdet · N mérés · ma) | a chipek alá |

Egy fül, ami ugyanazt mondja el máshogy, nem redundancia csak elvben: két
helyen kell karbantartani ugyanazt a számítást, és ott, ahol elcsúsznak,
a felhasználó két különböző igazságot lát. Ez már meg is történt egyszer —
az akcentus-leképzés négy fájlban élt külön, és a kártya más színt rajzolt,
mint a részletnézet.

## Hírek: cikk SZÖVEGE, nem weboldal

A `NewsReader` már nem böngészőt mutat. A cikk törzsét egy rejtett
`WKWebView` DOM-jából szedi ki (`ArticleExtractor`), és a szöveget NATÍVAN
rajzoljuk ki: a téma betűivel, színeivel, olvasható sorhosszal.

**Miért nem HTML-elemzés Swiftben:** a hírportálok oldala nem statikus. A
Google News hivatkozásai átirányítanak, több lap JavaScriptből tölti a
törzsszöveget, a jelölés pedig oldalanként más. A böngészőmotor a KÉSZ DOM-ot
adja, amiből a kiszedés már egyszerű. A pontszámozás annyi: kivágjuk a
sallangot (menü, lábléc, hirdetés, ajánló, süti-sáv), majd megkeressük azt a
szülőelemet, amely alatt a legtöbb bekezdés-szöveg van.

Mérve: CNBC és Index cikkeken teljes törzs, szerzővel és alcímekkel. Ahol nem
megy — fizetőfal, vagy csak görgetésre épülő szöveg —, azt KIMONDJUK, és
felkínáljuk a böngészőt (`SFSafariViewController`, olvasó nézettel). Csendben
félig üres oldalt mutatni rosszabb volna.

## Hírek oldal (2026-08-22-i redesign)

A handoff szerint, az app saját témarétegével — a handoff maga kéri, hogy a
kódbázis meglévő tokenjeivel épüljön újra, ne a prototípus fix palettájával.

- **Fix fejléc**: dátum-felirat, cím, szűrőcsipek (`Mind` / `Csak hírek` /
  `Nagy mozgás`). A csipek a képernyő vezérlőfelülete, ezért nem görögnek el.
- **Összegző kártya**: nettó hozzájárulás, kétoldalas sáv a nyers nyereség és
  veszteség arányáról, felirattal. A két per-soros százalék így kap
  viszonyítási pontot.
- **Tétel-kártyák**: monogram, név, ticker, ár + napi pirula, súlysáv
  `súly` / `az alapon` felirattal. Az ismétlődő koppintás-tipp egyszer
  szerepel, lábjegyzetként.
- **Kinyitható görbe** (egyszerre egy), `1H` / `6H` / `1É` tartománnyal — a
  tartomány globális, és a letöltött sorozat gyorsítótárazva van.
- **Hír a papírja alatt**, behúzva, 2 pt-es akcentusvonallal. Balra húzva
  elrejthető, visszavonás-buborékkal; az elrejtés TÚLÉLI az újraindítást
  (`hiddenNews` a tárolt állományban) — különben nem is volna elrejtés.
- **Piaci hírek** külön szekcióban, a csatorna vezető képével. Ahol a forrás
  nem ad képet, csíkos helyőrző marad — kitalált képet nem teszünk oda.

Amit NEM vettünk át: a valódi cégLOGÓK (harmadik fél védjegyei, engedélyhez
kötöttek — monogram marad), a prototípus kitalált összefoglalói (helyettük a
csatorna `<description>`-je, ha ad), és a saját tab bar (marad a natív
`TabView`, az app bevett mintája).

## Hírek a papírjuk alatt

A hírek fül két blokkja korábban párhuzamosan futott: fent a komponensek napi
mozgása, lent egy vegyes hírfolyam, amiben a cégekről szóló hírek is ott
voltak. Most a cég-hír a SAJÁT sora alá kerül, vékony színes vonallal
összekötve, a hírfolyamban pedig már csak az marad, ami egyik papírhoz sem
tartozik — a forint és a piac. Kétszer felsorolni ugyanazt zaj volt.

**A társítás szóhatáros** (`HoldingMatcher`), nem részsztring: a „meta"
különben beletalálna a „metaverse"-be és a „metal"-ba, a „micron" a
„micronutrient"-be. Egy pénzügyi hírfolyamban ez nem elméleti kockázat —
12 esetre mérve, a fenti három csapdával együtt.

A névtábla tömb, nem szótár: a szótár bejárási sorrendje nem determinisztikus,
és két találatnál ugyanaz a hír két futáskor más csoportba kerülne.

Papíronként legfeljebb három hír. Ha egy papírhoz aznap nincs, oda nem
kerül semmi — egy „nincs hír" sor tíz papírnál csak zaj.

## Függőleges ritmus: egy vonalban induló lapok

A négy fül háromféleképpen kezdte a tartalmat: a Portfólió és a Platformok
saját fejléccel 58 pt-nél, a Hírek a rendszer nagy címsorával 126 pt-nél
(mérve, képernyőképből). Most mind a három tartalmi fül SAJÁT fejlécet
használ, ugyanazzal a `DS.topPadding`-gel, és 82–87 pt között indul.

- `DS.topPadding` 58 → **78**. A tulajdonos szerint a tartalom túl magasan
  kezdődött, a Dinamikus Sziget alatt szorosnak hatott.
- `DS.bottomPadding` = **132**, egy helyen. A lebegő fül-sáv ráúszik a
  tartalomra; enélkül a görgetés végén az utolsó kártya alatta ragadt.

A Beállítások szándékosan marad a rendszer navigációs sávjánál: onnan
al-képernyőkre lépsz tovább, és ott a natív vissza-gomb a helyes.

**A Platformok panelje nem vágódik el élesen.** Csak felül volt kerekítve, és
ahol a tartalom véget ért, ott a mélyebb alapon éles vízszintes vonalként
látszott a pereme. Most a lap vászna maga a panel színe, a felső blokk viszi a
mélyebb alapot — így a panel alsó élének nincs hol látszódnia.

## HTML-entitások a hírcímekben

Az RSS-csatornák vegyesen használnak nevesített (`&amp;`, `&apos;`) és
számkódos (`&#39;`, `&#x27;`, `&#8211;`) entitásokat. A korábbi kód négyet
sorolt fel kézzel, ezért a képernyőn `Nvidia&apos;s` jelent meg.
A `HTMLEntities.decode` a számkódosakat általánosan oldja fel, a neveseket
táblából; az `&amp;` mindig utoljára, különben egy `&amp;#39;` kétszer
oldódna. 7 esetre mérve.

## „Mi lenne, ha…": benavigálás, nem lap

Teljes magasságban nyílik, és a natív, oldalra húzható vissza-gesztus jár
hozzá. Lapként alacsonyabb volt (az eredményhez görgetni kellett), és lefelé
kellett elhúzni a bezáráshoz.

**A feltevések minden változásnál mentődnek.** Először `.onDisappear`-re
mentettem, de kimértem, hogy a natív vissza-gesztussal kilépve nem fut le: a
tárolt állományban meg sem jelent a `scenario` kulcs, vagyis a beállításaid
nyom nélkül elvesztek volna. Ez rosszabb lett volna a korábbi „Kész" gombnál.

## Témaváltás állapotvesztés nélkül

A téma egy megfigyelhető tároló mögött áll (`ActiveTheme`), nem sima
globális változóban. Ezért a `DS.Color.*` olvasása a `body`-ban függőséget
regisztrál, és váltáskor pontosan azok a nézetek rajzolódnak újra, amelyek
tényleg használják.

Korábban `.id(store.themeID)` volt a `TabView`-on: az azonosító cseréje az
EGÉSZ nézetfát újraépítette, ezért a váltás úgy nézett ki, mintha az app
újraindulna — elveszett a görgetés és a kiválasztott fül.

## Sötét módban ne legyen világos sáv

A navigációs sáv `DS.Color.cream`-et kapott, ami **mindig világos** volt (a
vászon világos változata), függetlenül a rendszerbeállítástól. Sötét módban
ezért világos sáv ült a Beállítások és a „Mi lenne, ha…" tetején, alig
olvasható világos szöveggel. A szerep átnevezve `alwaysLight`-ra, hogy a neve
figyelmeztessen: háttérnek nem való, oda `canvas` kell.

## Téma szerinti app-ikon

Minden témához tartozik egy app-ikon, ugyanabból a színpárból
(`Tools/gen_icons.py` — az `AppTheme.swift`-ből olvassa ki a színeket, és
ugyanazt a szikragörbét rajzolja, mint az alapikon). Alternatív ikonként
kerülnek a csomagba (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`).

**Külön kapcsolóval, alapból kikapcsolva.** Az iOS az ikoncserénél
rendszerszintű értesítést dob fel, amit nem lehet elnyomni — témánként egyet
látni bosszantó, ezért a felhasználó dönt róla.

## Színrendszer: harmónia-sémák, nem kézzel írt hexek

Tizenkét téma, **mind generált** (`Tools/palette.py` + `Tools/gen_themes.py`,
újrafuttatható). Mindegyiknek MÁS a vezető árnyalata és MÁS a harmónia-sémája:

| téma | vezető | séma | akcentusok |
|---|---|---|---|
| Pasztell | 330° | osztott-komplementer | 330 / 120 / 180 |
| Tenger | 205° | komplementer | 205 / 25 / 55 |
| Erdő | 148° | osztott-komplementer | 148 / 298 / 358 |
| Grafit | 255° | analóg | 255 / 289 / 221 |
| Éjkék | 272° | triád | 272 / 32 / 152 |
| Szén | 330° | kettős | 330 / 30 / 160 |
| Bazalt | 185° | komplementer | 185 / 5 / 35 |
| Cseresznye | 15° | triád | 15 / 135 / 255 |
| Papír | 95° | triád | 95 / 215 / 335 |
| Hajnal | 350° | analóg | 350 / 24 / 316 |
| Homok | 65° | tetrád | 65 / 155 / 265 |
| Levendula | 295° | osztott-komplementer | 295 / 85 / 145 |

**Miért nem sRGB-ben:** az „azonos világosságú akcentus" követelmény sRGB-ben
nem ellenőrizhető. OKLabban a rögzített L tényleg azonos érzékelt világosság,
ezért mindhárom akcentus L = 0,76-on áll, és a gamutból kilógó színnél a
KRÓMÁT csökkentjük, nem a világosságot.

**A szövegszín mért, nem tippelt.** A generátor mindhárom akcentusra
kiszámolja a fehér és a saját sötét tónus WCAG-kontrasztját, és a jobbikat
teszi a témába. Az eredeti korall/fehér páros mért kontrasztja **2,25**; az új
témákban mindenhol **7,1 fölött** van.

**A Pasztell sem kivétel.** Az eredeti handoff-paletta korallal (35°) vezetett;
a tulajdonos kérésére 330°-ra (rózsa) került. A jellege megmarad — krémes
vászon, mély szilva héj —, mert az is a vezető árnyalatból származik. Az
eredeti hexek, ha bármikor vissza kellenének:
`canvasLight 0xFCEDE3 · cardLight 0xFFFFFF · inkLight 0x4A2545 ·
canvasDark 0x3A1B36 · cardDark 0x4A2545 · inkDark 0xFCEDE3 ·
shellDeep 0x3A1B36 · shell 0x4A2545 · accentWarm 0xF2966B ·
accentCool 0x8ED0BE · accentMid 0xB49BD8 · inkOnCool 0x1F4C41 ·
inkOnMid 0x33143A · negative 0xD2603A`.

**Miért látszott minden téma narancsnak:** az első akcentus mindig meleg
narancs volt, és azt viszi az app kiemelőszíne, az első platformkártya, a
jelvény, az összetétel-gyűrű legnagyobb szelete és a tartomány-chipek. Nem a
paletta volt szűk, hanem a szerepkiosztás.

**A nyereség és a veszteség NEM akcentus.** Rögzített árnyalaton állnak
(zöld 152°, piros 25°), csak a telítettségük követi a témát. Amikor az
akcentusok saját sémát kaptak, a második akcentus lehetett lazac vagy sárga —
és egy „+0,03%" pirosan jelent meg. Mérve, a Tenger témán.

Az akcentus→szín leképzés EGY helyen él (`AccentPalette.swift`). Korábban négy
fájlban külön `switch` volt, és el is csúsztak: a kártya a második akcentus
helyett a héjat rajzolta, a részletnézet a valódi akcentust — ugyanaz a
platform két képernyőn más színű volt.

## A főoldali görbe időbontása

`7N` / `30N` / `3H` / `MAX` chipek a közös görbe alatt, plusz egy `Ft` ⇄
`index` kapcsoló. A kettő MÁS kérdésre válaszol: „mennyim van hol" és
„melyik teljesített jobban". Az utóbbi korábban csak a Platformok fülön
létezett — ezzel a főoldal mindkettőt megadja.

## Dátumsáv a görbéken

Koppintásra vékony függőleges sáv + buborék: az adott nap dátuma és minden
vonal aznapi értéke. Ott is marad, amíg újra rá nem koppintasz — nem kell
nyomva tartani ahhoz, hogy elolvasd —, és amíg látszik, **húzással
mozgatható**.

- **A kiírt szám a NYERS érték**, nem a rajzolté. A görbét mozgóátlag simítja;
  ha a sáv a simított értéket mutatná, olyan összeget írna ki, ami sosem volt.
- **Vonalanként külön keresi a legközelebbi pontot**, mert a vonalak nem
  ugyanazokra a napokra esnek. Ha a legközelebbi pont 6%-nál messzebb van
  (a vonal ott még el sem kezdődött), az a sor kimarad — nem találunk ki értéket.
- **Miért koppintás és nem nyomva tartás:** a görbe `ScrollView`-ban ül, a
  `DragGesture`-t a görgetés elviszi, a `LongPressGesture`-rel sorbafűzött
  változat pedig meg sem szólalt. Mérve, nem feltételezve.
- **A húzás `highPriorityGesture`**, és csak akkor él, ha a sáv látszik
  (`GestureMask.none`, amikor nem). A `simultaneousGesture` kevés volt: a
  görgetés a vízszintes mozgást is magának kérte, és a sáv nem mozdult.
  Így rejtett sávnál a görbén is lehet görgetni, láthatónál az ujj a sávot viszi.

## Komponens-görbék: van történeti adat

A „nem érhető el ingyenes forrásból" állítás elavult volt. A Yahoo napi
záróárai élnek, és az alap nagy tételei Xetrán EUR-ban jegyzettek — ugyanabban
a pénznemben, mint a képernyő teteje. A `FundComposition.Slice.xetra` a
jeleket tárolja, **mindegyiket a Yahoo saját cégneve alapján ellenőrizve**
(`meta.longName`), nem tippelve: `MTE.DE` = Micron, `1YD.DE` = Broadcom,
`ABEA.DE` = Alphabet A. A TSMC-nek nincs Xetra-jegyzése — ott marad a napi
gyűjtés. A letöltés a részletnézet megnyitásakor fut, nem a listánál: tíz
sorhoz tíz hálózati kérés lenne azért, amiből legfeljebb egyet nyitsz meg.

## Számok beolvasása: a tizedesjelet KITALÁLJUK, nem feltételezzük

A Revolut a KÉSZÜLÉK nyelvén is exportál. Ugyanaz az egyenleg lehet
`"400 693,53 HUF"` (magyar), `"400,693.53 HUF"` (angol) vagy
`"400.693,56 HUF"` (német) — és a szóköz lehet sima, nem törhető (U+00A0),
keskeny nem törhető (U+202F) vagy vékony (U+2009).

A régi `HungarianCSV.amount` minden pontot ezreselválasztónak vett és a
vesszőt tizedesnek. Egy angol exportból ezért `400.69353` lett: a telefonon
**400 Ft** jelent meg 400 693 Ft helyett, a megtakarítás pedig „−99,90%"-ot
mutatott. A `HungarianCSV.number` most szabályt használ:

- ha vessző ÉS pont is van, a KÉSŐBBI a tizedesjel, a másik ezres;
- ha csak az egyik van, tizedesjel, ha pontosan egyszer szerepel és utána
  1–2 számjegy áll — különben ezreselválasztó;
- ha egyik sincs, egész szám.

15 esetre mérve, mindkét Revolut-formátumra és a Lightyear pontos alakjára.

## Visszatöltés: valódi múlt, nem „mi lenne, ha"

A `backfill` a Yahoo napi záróáraiból építi újra a görbét. Két dolgot csinál
másképp, mint korábban:

- **A múltbeli DARABSZÁMMAL számol**, nem a maival. A kivonatból ismerjük a
  halmozott darabszámot minden ügyleti napra (`quantityTimeline`), és két
  ügylet között az állandó. A mai darabszámmal visszaszámolva minden vásárlás
  előtti nap felfelé torzulna. Ahol a kivonat nem ér vissza, ott a nap
  KIMARAD — nullát írni azt állítaná, hogy akkor nem volt semmid.
- **Platformonként is kitölti** a `byPlatform` mezőt, és a meglévő napokba
  BELEFÉSÜL ahelyett, hogy eldobná magát. Korábban egy napon, ahol már volt
  mért Revolut-egyenleg, a visszaszámolt TBSZ-érték egyszerűen elveszett —
  ezért a kezdőképernyő közös görbéjén a TBSZ vonala nem épült fel.

## A közös görbe időtengelye

Minden platform ugyanarra az időtengelyre kerül: a vízszintes hely a
DÁTUMBÓL jön, nem a pont sorszámából. A megtakarításnak minden napra van
egyenlege (175 pont), a TBSZ-nek csak kereskedési napokra és csak az első
vásárlástól (55 pont) — sorszám szerint elosztva a két vonal ugyanarra a
szélességre feszült, tehát nem ugyanaz a nap volt egymás alatt.

## Napi, heti, havi eredmény

Három szám a főoldalon, mindegyik százalékban ÉS forintban. Két dolgot csinál
másképp, mint a legtöbb portfólió-app:

- **A befizetést levonja.** Ha a héten betettél 250 000 Ft-ot, a vagyonod
  250 000-rel nőtt anélkül, hogy egy fillért is kerestél volna. Az időszak
  eredménye ezért `záró − nyitó − nettó befizetés`. A belső átvezetések is
  beleszámítanak: az importáló mindkét lábat rögzíti, így ha mindkét számla
  benne van az ablakban, kiejtik egymást — ha csak az egyik, akkor az a pénz
  tényleg kívülről érkezett. Enélkül a megtakarításra átvezetett 398 476 Ft
  „+14 058% havi hozamként" jelent meg; mértük.
- **Csak azonos platformokat vet össze.** A Revolut-kivonatból visszamenőleg
  csak az adott számla napi egyenlege van meg, a TBSZ-é nem. Ha a mai teljes
  vagyont egy ilyen féloldalas naphoz mérnénk, a TBSZ teljes értéke nyereségnek
  látszana. Az app kiírja, hány platformot fog át az időszak.

Ha a nyitótőke a záróérték ötödénél kisebb — vagyis a számla lényegében az
ablakon belül épült fel —, a százalék helyén csak a forint áll: ott a „%" nem
hozamot mérne, hanem azt, hogy mennyire volt kicsi a nevező.

## Ki mozdult nagyot

Esemény-vezérelt napi összefoglaló: a nap nyertese és vesztese az alap nagy
tételei közül, 2,5%-os küszöb fölött, és a hír, ha a `ConstituentWatcher`
talált hozzá (az 3% fölött keres). Ha aznap semmi nem mozdult, a szekció nem
jelenik meg — egy „ma nem történt semmi" doboz minden nap csak zaj.

Minden sorban ott a **forintos hatás a te pénzedre**. Egy „NVIDIA −6%" főcím
ijesztő; hogy ez nálad −1 900 Ft, az megmondja, kell-e vele foglalkozni. Egy
3 757 papírból álló világindexben egyetlen név ritkán mozdít sokat, és ezt
kiírni kell, nem elkendőzni.

## Lélegző helyőrzők

Betöltés alatt nem pörgő kerék van, hanem a tartalom alakját mutató, lassan
(1,6 s) pulzáló helyőrző: így az érkező adattól nem ugrik szét a lap. A sorok
lépcsőzött késleltetéssel lélegeznek, hullámban. A „csökkentett mozgás"
rendszerbeállításnál nincs animáció, csak állandó halvány kitöltés.

## Témák

Kilenc téma, két családban. Mindegyiknek van világos és sötét változata — az
app a rendszert követi. A különbség a **héj**: a platform-részletek alapja.

- **Sötét héj** (Pasztell, Tenger, Erdő, Grafit, Éjkék, Szén): a részletlapok
  mindkét módban sötétek, ahogy az eredeti handoff tervezte.
- **Világos héj** (Papír, Hajnal, Homok): világos módban a részletlapok is
  világosak — fehér vagy halványan árnyalt alapon, sötét szöveggel.

Ezért **tilos `.white`-ot írni héj fölé**: arra `DS.Color.onShell(_:)` van, ami
követi a héjat. Világos héjon a fehér szöveg láthatatlan.

Az ikonok színe szerephez van kötve (`DS.Color.iconFX`, `iconPrice`,
`iconWinner`, `iconLoser`, `iconNews`, `iconTime`), témánként hangolt hat
hue-ból. Korábban minden sorikon a három platform-akcentusból jött, ezért a
lista egyhangú volt és a szín nem jelentett semmit.

## iPad: két arányos oszlop

`AdaptiveColumns` — `.regular` méretosztálynál két oszlop (54/46), alatta
egymás alatt. Nem `HStack`: az a tartalom belső méretéből osztana, és egy
grafikon meg egy kártyalista természetes szélessége semmit nem mond arról,
hogyan érdemes a lapot felosztani. A töréspont a méretosztály, nem a nyers
pontszélesség — a megosztott képernyős iPad fele ugyanolyan szűk, mint egy
telefon.

A két oszlop tartalma nagyjából egyforma magas: balra a számok, a görbe, a napi
összefoglaló és a magyarázatok, jobbra a kártyák és a műveletek.

## Számok, amiket ki kell írni

- **Hozam SZÁZALÉKBAN ÉS FORINTBAN.** A „+0,87%" önmagában nem mondja meg,
  mennyi pénzről van szó; a „+6 383 Ft" igen. Mindkettő ott van a kártyán, a
  részleteknél és az összegnél.
- **„Hiányzó adat", nem −100%.** Ha egy platformnak van befizetése, de nincs
  értéke (mert az egyik kivonat még nincs beolvasva), a régi kód −99%-ot
  írt ki. Ez félrevezető: nem veszteség, hanem hiányzó adat — az app most ezt
  mondja. Kamatozó számlánál a feltétel más: az nem VESZÍTHET pénzt, ezért
  ha az értéke a befizetés felénél kisebb, az adathiba. Az őr NEM a nullához mér: pár száz forint bennragadt készpénz már
  „nem nulla", és kivédené. Ehelyett azt nézi, van-e árfolyam MINDEN
  értékpapírra (`hasMissingQuotes`) — mérve: árfolyam nélkül a TBSZ
  „−99,92%"-ot mutatott a benne maradt 609 Ft készpénzből.
- **A grafikon nem tűnik el csendben.** Ha nincs elég mérés, kiírja, hogy
  miért és mit lehet tenni érte.

## Komponens-részletek

A hírek fülön és a platform-részleteknél az alap nagy tételei **koppinthatók**:
ár a Xetrán, napi mozgás, súly az alapban, a súllyal mért hatás, az app által
gyűjtött görbe, és a friss hír, ha van.

## Grafikonok

- **Közös görbe a kezdőképernyőn**: minden platform külön vonallal, forintban.
  Az összevetés fülön ugyanez 100-ra indexálva — ott az arányos elmozdulás a
  kérdés, itt az abszolút vagyon.
- **Lüktető végpont** minden vonal végén („itt tartunk most"). Két másodperces
  lélegzet, nem villanás — egy vagyonkijelzőn a villogás idegesítő.
- **Ügyletjelölők**: vétel menta, eladás korall pöttyel a görbén, a kivonatból
  kiolvasott dátumokon.

## Hírek

**Két blokk.** Felül az alap legnagyobb tételeinek NAPI MOZGÁSA — mind a nyolc
követhető komponens, súllyal és az alapra vetített hatással
(„Apple −1,70% · 4,0% súly · −0,07% az alapon"). Ehhez nem kell hírt hálózni,
csak árfolyamot, és ez válaszolja meg, hogy „hogyan alakulnak a részvények".

Alatta a hírfolyam, két forrásból — mindkettő ingyenes és kulcs nélküli
(a Yahoo hír-API végig 429-cel tolt vissza):

Két forrás, mindkettő ingyenes és kulcs nélküli (a Yahoo hír-API végig 429-cel
tolt vissza):

**Hét forrás**, magyar és angol vegyesen — a magyarok a forintot fedik le
(ez mozgat nálad a legnagyobbat), az angolok a világpiacot és az alap nagy
tételeit, amikről magyarul alig írnak: Portfolio, Index, VG, CNBC, MarketWatch,
Investing.com, Seeking Alpha. Mind ingyenes és kulcs nélküli.

Három relevancia-szint, ebben a sorrendben: **konkrét tétel** (az alapod egyik
nagy papírjáról szól) → **forint** → **piac**.

1. **Magyar gazdasági RSS** (Portfolio, Index, VG) — szűrve arra, ami a TE két
   mozgatórugódat érinti. A „forint" csak akkor számít, ha árfolyam-szövegkörnyezetben
   áll: a nyers hírfolyamban legtöbbször csak pénznem („50 ezer forintos támogatás").
   A devizás hírek előre kerülnek, mert nálad az árfolyam mozgat nagyobbat.
2. **Google News RSS** az alap komponenseire — **esemény-vezérelten**: hírt csak
   3%-nál nagyobb mozgásnál kérünk, és legfeljebb háromhoz. Minden megnyitáskor
   tíz hírlekérés a semmiért nem éri meg.

### Olvasás az appon belül

A cikkek nem dobnak ki Safariba. Két dolgot csinálunk másképp:
**előmelegítjük** a kapcsolatot a hivatkozott kiszolgálókhoz, amint a lista
megjelenik (`SFSafariViewController.prewarmConnections` — hivatalos API, a DNS-t
és a TLS-kézfogást intézi előre), és a tartalom **beúszik**, nem beugrik: amíg
tölt, a cím és a haladás látszik, nem üres fehér villanás.

### Egyedi részvények történeti árfolyama — nincs ingyen

Mérve 2026-08-22-én: a Yahoo chart tartósan **429**, a Stooq bot-ellenőrzés
(proof-of-work) mögé került, a Börse Frankfurt history-végpontja **403 / CORS**.

Ezért az app **maga gyűjti** a komponensek napi árát, ugyanúgy, ahogy a
portfólió-görbét — onnantól épül, amikor először megnyitod.

A **TBSZ-görbe viszont visszamenőleg is megvan**: a Lightyear-kivonatban nincs
napi egyenleg, de minden vételnél ismerjük a darabszámot ÉS az aznapi árat,
tehát az ügyleti napokra kiszámolható a valós érték. A mérésben ez 9 pont —
ritka, de igaz adat, nem becslés.

### Amit NEM tud, és miért

Elemzői célárak, P/E, EPS, béta, „bikák/medvék szerint" — ezek **fizetős
adatszolgáltatóktól** jönnek (a Lightyear előfizet rájuk). Ingyenes, kulcs
nélküli forrásból nem érhetők el megbízhatóan. Ha kellenek, az fizetős API-t
jelent, nem fejlesztési kérdés.

## Hogyan rajzoljuk a görbét

Három réteg, mind tulajdonosi kérésre („legyen ívelt, csak viszonyítás kell"):

1. **Logaritmikus skála**, ha a szóródás négyszeresnél nagyobb. Egy 2 800 →
   400 000 Ft ugrás lineáris tengelyen mindig függőleges vonal — nem a rajzolás
   hibája, hanem a skáláé. Logaritmikuson az azonos ARÁNYÚ változás azonos
   elmozdulás. Rövid szakaszon (7N/30N) marad a lineáris.
2. **Középre igazított mozgóátlag** az ADATON, nem a görbén. A befizetések
   egyetlen napon landolnak, tehát a sorozat lépcsős; egy függőleges ugrást
   semmilyen illesztés nem tud íveltté tenni. Az ablak a sorozat hosszához
   igazodik (0 / 3 / 5 / 9 nap).
3. **Monoton köbös illesztés** (Fritsch–Carlson) — garantáltan nem lő túl,
   sosem rajzol olyan értéket, ami nem volt.

**Zsákutca, hogy ne próbáljuk újra:** centripetális Catmull-Rom illesztéssel
próbáltuk lekerekíteni a sarkokat — minden lépcsőnél fel-le kilengett, és
sokkal rosszabb lett, mint a monoton változat. A simításnak az adaton kell
történnie, nem a görbén.

A felület **kiírja**, ha simított vagy logaritmikus — ami nem nyers adat, azt
meg kell nevezni.

## A görbe a kivonatból épül

A Revolut minden sorhoz kiírja az **egyenleget**, tehát a teljes időszak görbéje
benne van a fájlban — kár megvárni, hogy az app napról napra összemérje.
Az import kigyűjti a napi záró egyenlegeket és beolvasztja a mérési előzménybe
(`Snapshot.byPlatform`). A mérésben 174 napi pont jött a megtakarítási
kivonatból, 50 a folyószámláéból.

A meglévő napokat kiegészítjük, a hiányzókat létrehozzuk, a többi platform
aznapi értékéhez nem nyúlunk. Az értékpapír-mezők visszamenőleg nullák
maradnak — azokra nincs adat, és kitalálni tilos.

**A platform-részletek grafikonja a SAJÁT platform sorozatát rajzolja**
(`byPlatform[id]`), nem a teljes portfólióét. Korábban minden platform alatt
ugyanaz a portfólió-görbe jelent meg.

## TBSZ feltörés-kalkulátor

Megmutatja, mennyi maradna a kezedben, ha MA, a 3. év után vagy az 5. év után
törnéd fel — pontos dátumokkal és visszaszámlálóval.

**Az adóalap a nyereség, nem a teljes egyenleg.** Mindhárom szám a MAI
egyenleggel számol: nem jóslat arról, mennyi lesz a pénzed három év múlva,
hanem azt mutatja, a mostani nyereségedből mennyit vinne el az adó.

**A kulcsok szerkeszthető alapértékek, nem az app állításai a jogról.**
2026-08-21-i állapot két forrásból (RSM Hungary, szjabevallas2026.hu):
2025. január 1. UTÁN nyitott számlára 28% (15% szja + 13% szocho) / 18%
(10% + 8%) / 0%; az az előtt nyitottakra 15% / 10% / 0%, szocho nélkül.
A gyűjtőév alapján az app a megfelelőt javasolja, de átírható.

## Alap-összetétel

A VWCE top-10-e beégetett pillanatkép (justETF, 2026-08-21) — a Vanguardnak
nincs nyilvános API-ja, és az összetétel havonta frissül. A gyűrűn a
„többi 3 747 papír" szelet szándékosan uralja az ábrát: a top-10 az alapnak
csak **22,7%-a**. Ha csak a tízet rajzolnánk, az azt sugallná, hogy ők teszik
ki a portfóliót.

## Napi kamat-becslés

A megtakarítás egyenlege két import között **naponta gördül** a kivonatból
**mért** nettó napi kulccsal (kamatos kamattal, mert a Revolut is így ír jóvá).

**A kulcs mérve van, nem beégetve.** A beolvasó az utolsó hét kamatjóváírásból
számolja: `kamat / az azt megelőző egyenleg`. Csak az utolsó hétből, mert a
kulcs az időszakon belül is változhat (a mintában 1,25% → 2,49% → 2,50%).

**Miért nem a meghirdetett EBKM:** a ténylegesen jóváírt nettó kamat annak
72%-a — a mérésben 2,50% helyett **1,80%** (28% levonás). A meghirdetett
kulccsal az app rendszeresen többet mutatna a valóságnál.

A becslés a felületen **meg van jelölve**: kiírja, mennyi belőle a becsült
kamat és hány napja gördül import nélkül. Hét nap után figyelmeztet, hogy
ideje friss kivonatot beolvasni — az visszaigazítja a valósághoz.

Amit a becslés nem tud: az időközbeni be- és kifizetéseidet, és ha a Revolut
kulcsot változtat. Ezért kell a rendszeres import.

## Amit az app NEM követ magától

**Nem tudja a valós egyenleget kivonat nélkül.** A `performRefresh` csak ETF-árfolyamot és
devizát kér le; a `cashAssets` egyenlegéhez kizárólag az import és a kézi
szerkesztés nyúl. A megtakarítás egyenlege tehát a **legutóbbi kivonat záró
értékén áll**, amíg új kivonatot nem olvasol be.

Ezért hordoz a `CashAsset` egy `asOf` dátumot, és ezért írja ki a felület,
melyik napi kivonatból való — enélkül a szám némán öregedne.

**Miért nem vetítjük előre:** a kivonatban a meghirdetett kamat kétszer is
változott (1,25% → 2,49% → 2,50%), tehát az előrevetítés találgatás lenne.
Ráadásul a ténylegesen jóváírt **nettó** kamat mérve 1,80% évesítve — pontosan
a meghirdetett 2,50% 72%-a (28% levonás). A meghirdetett kulccsal számolva az
app rendszeresen többet mutatna a valóságnál.

## Újraimport és a grafikon

**A mérési előzmény túléli az újraimportot.** Az import soha nem nyúl a
`snapshots`-hoz: azok mérések, nem a kivonatból származnak. Csak a napi
pillanatkép-rögzítő és a visszatöltés írja őket.

**De a mai mérés felülíródik.** Ha ma importálsz egy frissebb kivonatot, a mai
pillanatkép az új egyenleggel cserélődik, a korábbi napok viszont a régi
egyenleget őrzik. A görbén ezért **lépcső** jelenik meg az import napján — ami
azt mutatja, mikor *értesült* az app a kamatról, nem azt, mikor keletkezett.

**Figyelem:** ha később SZŰKEBB időszakról importálsz (pl. május–augusztus a
március–augusztus helyett), az adott platform befizetései lecserélődnek arra,
ami az új fájlban van, és a nyitó egyenleg újraszámolódik. A számok
önmagukban konzisztensek maradnak, de az ablak lerövidül — és ha a két Revolut
kivonat így eltérő időszakra szól, a belső átvezetések megint nem csengenek ki.

## Elemzések

- **Devizahatás szétválasztva** — a forintos eredményt ár- és devizahatásra bontja.
  A levezetés: `deviza = Σ beker_EUR_i × (mai_fx − fx_i)`. Ez oldja fel, hogy
  ugyanaz a pozíció euróban mínuszban, forintban pluszban állhat.
- **XIRR** — befizetés-súlyozott éves hozam bisectióval (nem Newton: lassabb,
  de nem szalad el). Fél évnél rövidebb előzménynél az app figyelmeztet, mert
  ilyen időtávot évesíteni félrevezető.
- **Díj-kimutatás** — típusonként (befizetés / átváltás / kereskedés), minden
  devizát a saját napi árfolyamán forintosítva, és a befizetések arányában.

**Adótanácsot nem ad és nem is fog.** A TBSZ-nél csak naptári dátumokat számol.

## Hogyan kerül be egy kivonat

Három út, mind ugyanabba a beolvasóba fut:

1. **Megosztólap** (a legrövidebb) — a Revolut/Lightyear appban Export →
   Megosztás → **Portfólió**. A kiterjesztés csak *leteszi* a fájlt az App Group
   `inbox/` mappájába; a beolvasás az app indulásakor történik, mert ahhoz
   hálózat kell (devizatörténet a forintos bekerülési értékhez), a
   megosztás-kiterjesztés pedig rövid életű, szűk memóriakeretű folyamat.
2. **iCloud-mappa** — a Fájlok appban megjelenik egy **Portfólió** mappa
   (`NSUbiquitousContainers`); ide Macről is bedobhatsz CSV-t. Az app
   induláskor áthozza a postaládába. Az iCloud lusta: a még le nem töltött
   fájlokat csak megjelöljük letöltésre, és a következő indításkor kerülnek sorra.
3. **Fájlválasztó** — `···` menü → Kivonat beolvasása.

A fájlnév mindhárom úton megőrződik, mert a számlaazonosító abból derül ki.
Hibás fájlt is eltávolítunk a postaládából, különben minden induláskor újra
próbálkozna és újra hibát mutatna — az eredeti fájl megvan a felhasználónál.

## Kivonat-import — három formátum

A beolvasó a **FEJLÉC alapján** ismeri fel, melyik kivonatot kapta, nem a
fájlnévből. Mindhárom más szerkezetű, és a különbségek nem kozmetikaiak:

| | Dátum | Tizedes | Sajátosság |
|---|---|---|---|
| Lightyear | `11/08/2026 08:54:05` | pont | a díj a Gross-ban van |
| Revolut megtakarítás | `2026. máj. 1.` | **vessző** + pénznem-utótag | **KÉT fejléc** a fájlban |
| Revolut folyószámla | `2026-03-05 20:42:28` | **pont** | az `Egyenleg` TERMÉKENKÉNT értendő |

### Csapdák, amiket mérés fogott meg

- **A két Revolut-fájl eltérő tizedesjelet használ.** A folyószámla `21607.94`
  pontját ezresjelnek venni **százszoros** hibát ad. Ezért van külön
  `plainAmount` (pontos) és `amount` (vesszős) elemző.
- **A folyószámla-kivonat `Egyenleg` oszlopa a sor TERMÉKÉRE vonatkozik.**
  Globálisan olvasva a megtakarítás egyenlegét adja vissza (400 693 Ft), nem a
  folyószámláét (21 608 Ft).
- **A megtakarítási fájlban menet közben megváltozik a fejléc** (`Nettó kamatláb`
  → `EBKM`), ezért minden „Dátum"-mal kezdődő sort fejlécnek veszünk.
- **A díj külön terheli az egyenleget**, nem az összegben van
  (−499,52 összeg + 5,00 díj → −504,52 egyenlegváltozás).
- **Csak `ELVÉGEZVE` tételek** számítanak; a függőben lévő és a visszatérített
  sorok beszámítása kétszer mozgatná az egyenleget.

### Belső mozgás

A folyószámla → megtakarítás átvezetés `isInternal` jelölést kap: a **platform**
saját mérlegében benne van (különben a megtakarítás összes pénze hozamnak
látszana), a **teljes vagyon** befizetéséből viszont kimarad — különben ugyanaz
a forint kétszer számítana befizetésnek.

Ellenőrzésül: a folyószámla hozama pontosan **0,00%** (költési számla nem
termel), a megtakarításé pontosan a jóváírt kamat.

**Azonos időszakra kért kivonatokkal a könyvelés forintra zár**: a belső
átvezetések összege pontosan 0, és az összesített hozam pontosan a valódi
nyereség (értékpapír-hozam + jóváírt kamat). Eltérő időszakoknál marad maradék.

**A nyitó egyenleg KÜLSŐ tétel**, nem belső: a megfigyelt időszak előtt került a
számlára, tehát tőke, nem hozam. Belsőként jelölve kimaradna az összesített
befizetésből, és pont annyival mutatna több nyereséget, amennyi a nyitó összeg.

## Kivonat-import

A Lightyear „Számlakivonat" CSV-jét olvassa (`···` menü → Kivonat beolvasása).
Ebből jön a darabszám, az euró átlagár, a forintos bekerülési érték, a
befizetések és a díjak.

**A forintos bekerülési érték a TÉNYLEGES átváltási árfolyamon számol**, nem az
ECB középárfolyamán: a kivonat Conversion sorain az EUR oldal `FX Rate` mezője
adja meg (ha 100 fölötti, akkor EUR/HUF; ha 1 körüli, akkor EUR/USD, azt nem
használjuk). A kettő közti különbség a szolgáltató árrése — a mérésünkben
1 130 Ft volt 735 132 Ft-ra vetítve.

A TBSZ gyűjtőévét a legkorábbi befizetés évéből veszi, nem kell megadni — de
**csak korábbra mozdulhat, sosem későbbre**: egy később exportált, szűkebb
időszakú kivonatban az első befizetés napja már nem szerepel, és a beolvasó
tévesen egy későbbi évet számolna.

### Több számla

Az import **összefésül, nem felülír**: csak az adott számla tételeit cseréli.
A számlaazonosító a fájlnévből jön (`AccountStatement-LY-4WY38ZH-…` → `LY-4WY38ZH`),
mert a CSV-ben nincs ilyen oszlop. A kulcs az **(ISIN, számla) pár**, nem az ISIN
önmagában: 2027-ben új TBSZ nyílik, és ugyanaz a VWCE állhat mindkettőben, más
gyűjtőévvel és más bekerülési árral. Felülírásnál a második import kitörölné az
elsőt. Egynél több számlánál a pozíciósorok számla-címkét kapnak.

## Widget

Két külön widget (nem egy konfigurálható — úgy a galériában nem derülne ki,
hogy több nézet is van):

- **Portfólió értéke** — small, medium, és a zárolási képernyőre inline/circular/rectangular
- **A számla megoszlása** — medium, large

A widget **saját maga kér le árfolyamot** óránként, nem csak az app utolsó
mentését mutatja — különben egy ritkán megnyitott appnál napokig állna rajta
elavult szám. Ha a lekérés nem megy (repülőgép mód, rate limit, elfogyott
WidgetKit-büdzsé), akkor az utolsó mentett állapotot mutatja, de a fejlécben
megjelenik egy óra-ikon: az app nem tesz úgy, mintha friss adata lenne.

Adatcsere: App Group (`group.hu.halasz.portfolio`) `portfolio.json`. iOS-en a
group-azonosító **nem** kap team-prefixet — macOS-en kapna, ott a sandbox
megköveteli.

### Két build-buktató, amibe belefutottunk

1. `xcodebuild` **`-allowProvisioningUpdates`** nélkül elhasal az extension
   app-id és az App Group automatikus regisztrációján.
2. Az `NSExtension` szótárat **nem lehet** `INFOPLIST_KEY_*` kulcsokkal
   előállítani (a generátor csak lapos kulcsokat tud) — enélkül a telepítés
   `Invalid placeholder attributes` hibával bukik. Ezért van külön
   `Widgets/Info.plist`.

### Amit neked kell megtenned

A widget kezdőképernyőre húzását nem lehet megbízhatóan scriptelni — azt a
galériából kézzel kell hozzáadni. A fenti képek egy ideiglenes előnézet-panelből
készültek, ami valódi widget-méretekben renderelte a nézeteket; a panelt
a mérés után eltávolítottam.

**Zárolási képernyő:** az inline/rectangular widget a portfóliód értékét a
lezárt telefonon is kiírja. Ha ez nem kívánatos, egyszerűen ne add hozzá —
a kódból nem kell törölni.

## Futtatás

Szimulátoron:

```
./"Portfólió indítása.command"
```

Csatlakoztatott iPhone-ra:

```
./"Telefonra telepítés.command"
```

Az Xcode-projekt: `Portfolio.xcodeproj` — de **az XcodeGen generálja a
`project.yml`-ből**. Ami build-beállítást az Xcode felületén állítasz, azt a
következő `xcodegen generate` eldobja; mindig a `project.yml`-t szerkeszd.

### Eszköz-telepítés buktatói

- **A `devicectl` azonosítója NEM az `xcodebuild -destination` id-je.** A devicectl
  saját UUID-t ad (`F1C6000E-…`), az xcodebuild a hardveres ECID-et várja
  (`00008132-…`). A kettőt összekötni hibás; ezért fordítunk
  `generic/platform=iOS`-re, és telepítünk külön a devicectl azonosítójával.
- **`grep available` nem működik szűrésnek**: az „unavailable" tartalmazza az
  „available" szót, így a le sem csatlakoztatott telefont is kiválasztja.
  `grep -v unavailable` kell.
- **Az App Group fizetős fejlesztői fiókot igényel.** Ingyenes Apple ID-vel az
  app elindulna, de a widget soha nem kapna adatot.
