# Import-automatizálás: kutatás és terv

> **2026-08-22 este: az 1–2. szint MEGÉPÜLT.** Részletek a README
> „Import-automatizálás" szakaszában; a 3. szint (Enable Banking) tudatosan
> elhagyva — a tulajdonos döntése: „nem hiszem, hogy feltétlen kell ennél jobb".

*2026. 08. 22. — minden állítás mellett ott van, hogy mérés, dokumentáció vagy
nyitott kérdés. Ami nyitott, azt nem építjük be, amíg nem igazolt.*

## Honnan indulunk — a mai út, lépésekben

| forrás | mai lépések | gyakoriság |
|---|---|---|
| OTP bankszámla + hitelkártya | MobilBank → Továbbiak → Dokumentumok → letöltés → megosztás az appba (2 fájl) | havi |
| Revolut (2 számla) | Revolut app → kivonat → CSV export → megosztás (2 fájl) | havi |
| Lightyear | web → Documents → CSV letöltés → megosztás | havi |
| iCloud-mappa | Macről bemásolás → app indítása | eseti |

Összesen **5 fájl havonta, forrásonként 3–5 koppintás**, plusz az app megnyitása.
A cél nem a nulla koppintás (az PSD2 nélkül nem megy), hanem hogy a havi kör
**egyetlen mozdulat** legyen, és semmi ne vesszen el, ha elfelejted.

A kód felmért reései (2026-08-22-i audit, mind mérve):

- **Nincs `scenePhase`-kezelés** — a postaláda csak hidegindításkor ürül. Ha az
  app a háttérben fut, és megosztasz egy fájlt, majd visszaváltasz, NEM
  dolgozódik fel, csak a következő teljes újraindításnál.
- **Nincs `NSMetadataQuery`** — az iCloud-mappát csak indításkor nézzük meg.
- **Nincs `BGAppRefreshTask`** — az app a háttérben soha nem gyűjt.
- **Nincs App Intent** — a Parancsok app nem lát semmit az appból.
- **Nincs dokumentumtípus-regisztráció** — a Fájlokban egy PDF-nél a
  „Megnyitás ezzel" lista nem ajánlja fel az appot, csak a megosztólap.

## 1. szint — súrlódáscsökkentés az appon belül (külső függés nélkül)

Ezek együtt kb. egy napi munka, és a kör felét megspórolják.

**1a. Előtérbe kerüléskor postaláda-ürítés** (`scenePhase → .active` →
`processInbox`). A fenti rés javítása; enélkül a többi pont értelmét veszti,
mert a felhasználó azt látja, hogy „nem történt semmi".

**1b. Élő iCloud-figyelés** (`NSMetadataQuery` a ubiquity-konténeren). Amíg az
app nyitva van, a Macről bedobott fájl magától megérkezik és feldolgozódik —
toast jelzi, mi olvasódott be. Az iCloud lustaságát már kezeljük
(`startDownloadingUbiquitousItem`).

**1c. `BGAppRefreshTask`**: naponta egyszer háttérben begyűjti az
iCloud-mappát és újraütemezi a kártya-emlékeztetőt. Fontos őszinteség: az iOS
a futtatást NEM garantálja (használati mintától függ) — ez kényelmi réteg,
nem ígéret. A widget már most is menti a napi mérést, az marad a gerinc.

**1d. Dokumentumtípus-regisztráció** (`CFBundleDocumentTypes`: PDF, CSV) +
`onOpenURL`. A Fájlokból/Mailből egy kivonat „Megnyitás — Portfólió" egyetlen
koppintás, megosztólap nélkül.

**1e. App Intent: „Kivonat beolvasása"** (fájl-paraméterrel) és „Portfólió
frissítése". Ez nyitja ki a Parancsok appot: a felhasználó saját automatizálást
építhet (pl. egy gombhoz kötve), és a Spotlightból is hívható.

## 2. szint — Mac-oldali automatizálás (nulla költség, ma működik)

A kivonatok a Macre érkeznek (letöltés vagy e-mail). A Mac tud olyat, amit az
iPhone nem: mappát figyelni és szabály szerint cselekedni.

**2a. Letöltés-figyelő.** `launchd` agent `WatchPaths`-szal a `~/Downloads`-on:
ha kivonat-mintájú fájl érkezik (`Bankszámlakivonat_*.PDF`,
`Hitelkártya számlakivonat_*.pdf`, `savings-statement_*.csv`,
`account-statement_*.csv`, `AccountStatement-LY-*.csv`), átmásolja az iCloud
Portfólió-mappába. Innentől a havi kör: letöltöd a kivonatot a bank oldaláról,
és KÉSZ — a többit a Mac + az 1b/1c pont intézi. ~1 óra munka, ebből script +
plist a repóba kerül (`Tools/`).

**2b. Mail-szabály** (feltételes). HA a bank/bróker e-mailben küldi a kivonatot
csatolmányként, egy Mail.app-szabály + AppleScript a csatolmányt ugyanabba a
mappába teszi. **Nyitott kérdés, neked kell megnézned:** az OTP elektronikus
levelezésre átállt (2025. június), de hogy a PDF csatolmányként jön-e, vagy
csak értesítés a Dokumentumok menübe, azt a saját postafiókod mondja meg.
A Revolutnál és a Lightyearnél a keresés nem igazolt automatikus havi
kivonat-e-mailt — ha a beállításaikban van ilyen kapcsoló, ez az út él.

## 3. szint — teljes automatizálás (PSD2 aggregátor)

A kutatás eredménye, forrásokkal:

- **OTP közvetlen PSD2**: engedélyes AISP-knek szól (eIDAS tanúsítvány + MNB),
  magánszemélynek nem elérhető. A fejlesztői gazdagépek nem válaszolnak
  (mérve: DNS-hiba / 404).
- **GoCardless (Nordigen)**: az ingyenes szint (50 bank/hó) **2025 júliusa óta
  zárva van új regisztrációk előtt** — kiesett.
- **Salt Edge, Tink, Plaid**: céges szerződés kell — magáncélra nem reális.
- **Enable Banking**: ✅ a legjobb jelölt. Ingyenes „Restricted Production"
  hozzáférés Európában **a saját magad által összekötött számlákra** — pontosan
  a mi esetünk. A magyar piaci dokumentációjuk szerint az **OTP lefedett**
  (redirect-alapú SCA az InternetBank/MobilBank azonosítással), továbbá K&H,
  Raiffeisen, MBH.

**Amit az Enable Banking-ről még igazolni kell, regisztráció után** (a nyilvános
dokumentáció nem mondja ki): a hozzájárulás érvényessége (90 vagy 180 nap — ez
dönti el, milyen gyakran kell újra beengedned), a lekérhető tranzakciótörténet
mélysége, és hogy a Revolut EEA szerepel-e a lefedettségben.

**Architektúra, ha megéri:** az app KÖZVETLENÜL hívja az Enable Banking API-t
(saját kulccsal, Keychainben tárolva) — nincs saját szerver, az adat a
készülék és az aggregátor között mozog. A redirect-SCA miatt az összekötés és
a megújítás kézzel történik (Safari-ablak), utána a lekérés automatikus.
Fontos: ez a **folyószámla-tranzakciókat** hozná; a hitelkártya-kivonat
összesítői (minimum fizetendő, határidő) és a Lightyear ügyletek **nem
jönnek PSD2-n** — a kivonat-import ezekhez megmarad.

## Ajánlott sorrend

| lépés | haszon | munka | függés |
|---|---|---|---|
| 1a scenePhase | valódi bug-jellegű rés zárása | 1 óra | — |
| 2a Mac letöltés-figyelő | a havi kör 1 mozdulat lesz | 1 óra | — |
| 1b élő iCloud-figyelés | a Macről jövő fájl azonnal beolvasódik | fél nap | 1a |
| 1d dokumentumtípus | egykoppintásos megnyitás | 1 óra | — |
| 1e App Intents | Parancsok-automatizálás | fél nap | — |
| 1c BGAppRefresh | háttérgyűjtés (nem garantált) | fél nap | 1b |
| 2b Mail-szabály | e-mailes kivonatnál nulla mozdulat | 1 óra | **te**: jön-e csatolmány |
| 3 Enable Banking | tranzakciók kivonat nélkül | több nap | **te**: regisztráció + consent-idő igazolása |

A 3. szintet akkor érdemes meglépni, ha az 1–2. szint után még mindig
hiányzik valami — a kivonat-import önellenőrzése (a bank saját összesítőjéhez
mérünk) olyan garancia, amit az API-s út nem ad ingyen.

## Függelék: Enable Banking részletesen (2026-08-22, második kutatási kör)

**Mi ez.** Finn open banking-aggregátor, amely engedélyes AISP-ként áll a
bankok PSD2 API-jai előtt. A „Restricted Production" mód lényege: az
alkalmazásod CSAK azokat a számlákat éri el, amelyeket TE magad kötöttél
össze a saját banki azonosításoddal — és ez a mód **ingyenes**. Pontosan erre
a személyes esetre való; a self-hosted pénzügyi appok közössége (Firefly III)
bevett módon ezt használja.

**Hogyan működne nálunk:**
1. Regisztráció a vezérlőpultjukon (e-mail), új alkalmazás „Production"
   módban → státusza „Inactive". RSA-kulcspárt kapsz, a privát kulcs nálad.
2. Aktiválás: „Activate by linking accounts" → átirányítás a bank SCA-jára
   (OTP-nél a MobilBank-os jóváhagyás) → az app „active (restricted)" lesz.
3. Az app innentől a privát kulccsal aláírt JWT-vel (max. 24 óra érvényű)
   hívja az API-t: számlák, egyenlegek, tranzakciók. A kulcs a Keychainben,
   szerver nincs.
4. A hozzájárulás érvényessége bankfüggő, tipikusan **180 nap** — lejáratkor
   újra be kell engedni (ugyanaz a redirect). Az app kiírná: „a hozzáférés
   X nap múlva lejár".

**Egy fontos működési részlet:** több banknál a TELJES tranzakciótörténet
(1–3 év) csak az azonosítás utáni ~1 órás ablakban kérhető le; utána a PSD2
szerint jellemzően 90 napra lehet visszanézni. Vagyis minden consent-megújítás
után azonnal teljes szinkront kell futtatni — ezt a kód betartaná.

**Mit adna:** OTP folyószámla (+ valószínűleg Revolut) tranzakciók és
egyenlegek automatikusan — a Kiadások fül kivonat-letöltés nélkül frissülne.

**Mit NEM adna:** a hitelkártya-kivonat összesítőit (minimum fizetendő,
határidő — ezek kivonat-szintű adatok, nem PSD2-esek) és a Lightyeart
(bróker, nem bank). A PDF-import ezekhez megmaradna.

**Őszinte kompromisszum:** a kivonat-importnál minden adat az eszközön marad;
itt egy harmadik fél (az Enable Banking infrastruktúrája) ül az adatfolyamban.
Ingyen ez az ára.

**Regisztráció után igazolandó** (a nyilvános dokumentáció nem mondja ki):
Revolut a lefedettségi listán; kérés-limitek; hogy a teljes (nem-restricted)
módhoz kötelező KYB a restricted módot tényleg nem érinti-e.

**Becsült munka:** vezérlőpult-beállítás ~15 perc (a te részed), app-oldal
1–2 nap (JWT-aláírás, bank-redirect kezelés, API-kliens, betöltés a meglévő
`ExpenseEntry`/napi egyenleg útvonalakra).

### Biztonság és hitelkártya (2026-08-22, harmadik kör)

- **Engedély ellenőrizve:** az Enable Banking Oy a finn felügyelet (FIN-FSA)
  által bejegyzett AISP; az EEA-passportolása a tagállami regiszterekben
  (pl. a lett jegybank nyilvántartása) nyilvánosan látszik.
- **Csak olvasás.** Az AIS-hozzájárulással pénzt mozgatni NEM lehet — a
  fizetés-indítás (PIS) külön szolgáltatás, külön hozzájárulással, amit nem
  kérnénk. A legrosszabb eset (az aggregátor kompromittálódik) adatkitettség,
  nem pénzmozgás.
- **Jelszó nem utazik.** Az OTP saját OAuth2-átirányításán azonosítasz (a bank
  dokumentuma szerint), és a hozzájárulás az OTPdirektben BÁRMIKOR
  visszavonható; magától is lejár legfeljebb ~180 nap után.
- **Hitelkártya:** az OTP nyilvános PSD2-összefoglalója számlatípus-listát nem
  ad — hogy a hitelkártya-számla összeköthető-e, azt az OTP engedélyező
  képernyője dönti el az összekötés pillanatában. Ha nincs ott, marad a
  PDF-kivonat, amiből a forgalmat ma is beolvassuk; a kivonat-szintű mezők
  (minimum fizetendő, határidő) PSD2-n amúgy sem jönnek.

## 3. szint MEGÉPÜLT — mérési napló (2026-08-22 este)

**Regisztráció.** Két buktató, mindkettő az Enable Banking űrlapján:
1. Egyedi séma (`portfolio://`) NEM fogadható el — csak `https`.
2. `https://localhost/...` sem: éles módban külső, elérhető cím kell.
3. A Privacy/Terms URL Production módban KÖTELEZŐ (a súgószöveg
   „(optional)"-t ír, az a Sandboxra vonatkozik).

Megoldás: GitHub Pages (`Pages/` a repóban → `lacus-md.github.io/portfolio/`).
A redirect cél sosem töltődik be, ezért 404 marad — ez helyes.

**Két valódi hiba a kliensben, mérve:**
- **A PKCS#8 DER-olvasó a külső `SEQUENCE`-t átlépte** ahelyett, hogy
  belelépett volna; utána a verziómezőt a puffer végén kereste. Minden
  valódi kulcs betöltése elbukott volna — és ez csak a banki jóváhagyás
  UTÁN derült volna ki. Javítva; a tulajdonos RSA-4096 kulcsán ellenőrizve:
  betöltés + JWT-aláírás + élő `/application` hívás → HTTP 200.
- **Egyetlen munkamenetet tárolt** (`sessionID: String?`), tehát a második
  bank összekötése némán felülírta volna az elsőt. Átalakítva
  `connections: [EBConnection]`-re; a szinkron bankonként fut, és az egyik
  bank lejárt engedélye nem akasztja meg a többit.
- Mellékesen: a hozzájárulás felső korlátja a mi oldalunkról 90 nap volt —
  fölösleges önkorlátozás, 180-ra emelve (a bank maximuma úgyis felülírja).

**Az `ASWebAuthenticationSession` nem járható út** ehhez az API-hoz: egyedi
sémát kívánna, az meg tiltott. A jóváhagyás beágyazott `WKWebView`-ban fut,
és a visszairányítást a betöltés ELŐTT kapjuk el (`BankAuthWebView`).

**Lefedettség — eldőlt:** az OTP folyószámla és a Revolut folyószámla
összeköthető; a **Revolut megtakarítási** és az **OTP hitelkártya** számla
NEM (nem „fizetési számla" a PSD2 értelmében). Ezek maradnak kivonatból —
ahogy a kártya minimum fizetendő/határidő mezői is, amiket a PSD2 elvből
nem ad.
