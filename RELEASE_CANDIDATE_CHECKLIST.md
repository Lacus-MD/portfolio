# Portfolio 1.0 Release Candidate checklist — Build 38

This checklist is the no-device verification path for Build 38. It is safe to
run without bank credentials, signing secrets, or a connected phone.

- [x] XcodeGen regenerated `Portfolio.xcodeproj` from `project.yml`.
- [ ] Unit-test target compiles for iPhoneOS without signing; the current host
  run remains deferred because the unit-only invocation is blocked by Xcode's
  `ObservationMacros.ObservableMacro` plug-in sandbox restriction.
- [x] Full iPhoneOS Release scheme builds successfully with signing disabled;
  the crypto result-builder error is resolved.
- [x] All app, widget, share-extension, watch app, and watch widget targets
  compile in the Build 38 Release configuration. The build reports only the
  pre-existing DateFormatter and watch-target warnings.
- [x] Build number is read from the generated app bundle Info.plist.
- [x] iCloud sync envelope round-trip and revision conflict tests compile in
  the iPhoneOS unit-test target.
- [x] The app pulls remote portfolio revisions on startup/foreground and
  publishes successful local saves to the existing iCloud Documents container.
- [x] Lightyear fractional quantities with three or more decimal places are
  parsed as decimals rather than thousands-separated integers.
- [x] Import- és értékellenőrző központ jelzi a hiányzó árfolyamot, régi
  egyenleget, szokatlan darabszámot és nem párosított átvezetést.
- [x] WebKincstár export sorai megőrzik az ISIN/névérték/bekerülés/lejárat/
  kamat mezőit, ha az export tartalmazza őket.
- [x] Az állampapír-lejáratok megjelennek a kamat- és lejárati naptárban.
- [x] Crypto/wallet export HUF mérési értékkel, opcionális bekerüléssel és
  duplázás elleni platform-egyeztetéssel kerül be; nincs tranzakciós útvonal.
- [x] Lightyear főszámla-exportból az ISIN nélküli crypto Buy/Sell sorok (ETH,
  SOL, UNI és ismert tokenek) nettó mennyiséggel, történeti bekerülési értékkel
  és látható aktuális-ár hiány jelzéssel kerülnek be.
- [x] CoinGecko HUF árfolyamréteg egyetlen kérésben frissíti az ismert crypto
  tokeneket; a piaci egységár, 24 órás változás és időbélyeg külön mezőben
  marad, és az aktuális érték nem írja felül a bekerülési értéket.
- [x] Előtérben 45 másodperces crypto-frissítés fut; jelentős crypto-mozgás a
  meglévő, napi egyszeri piaci értesítési csatornán jelenik meg.
- [x] Enable Banking provider-állapot látható; élő API-hívás csak ellenőrzött,
  aktív konfigurációval indul, a privát kulcs készülék-helyi Keychainben marad.
- [x] `git diff --check` passes.
- [x] Importer fixtures contain no personal or bank data.
- [ ] Runtime unit/UI tests — deferred because CoreSimulatorService cannot
  provide a simulator in this environment; the unit-test target compiles.
- [ ] Physical iPhone installation and smoke test — deferred because the
  configured device is unavailable.
- [ ] Cross-device iCloud runtime sync — deferred until two signed Apple
  devices are available; the build has no live iCloud credentials in tests.
- [ ] Five-to-seven-day TestFlight observation — deferred until a device and
  App Store Connect upload are available.

Build 38 implementation is complete for the CoinGecko crypto quote layer and
Build 36 implementation is complete for the import-reconciliation,
WebKincstár-detail, crypto-export, provider-gating and portfolio-value
reconciliation slices, plus Lightyear crypto transaction recognition and the
scheduled market-close notification. Release and
runtime verification remain deferred because the host cannot start the
CoreSimulator service and the physical iPhone is unavailable; the existing
cloud-sync implementation was not changed.

The final Release Candidate must not be described as physically validated or
TestFlight-observed until the two deferred checks are completed.
