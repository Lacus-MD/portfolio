# Portfolio 1.0 Release Candidate checklist — Build 31

This checklist is the no-device verification path for Build 31. It is safe to
run without bank credentials, signing secrets, or a connected phone.

- [x] XcodeGen regenerated `Portfolio.xcodeproj` from `project.yml`.
- [x] Unit-test target compiles for iPhoneOS without signing.
- [ ] All app, widget, share-extension, watch app, and watch widget targets
  compile in the Build 30 Release configuration; the retry is currently
  blocked by Xcode's `ObservationMacros` plugin service on the host.
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

Build 31 implementation is complete for these two feature slices. Release
and runtime verification remain deferred because the host cannot start the
CoreSimulator service and the physical iPhone is unavailable; the existing
cloud-sync implementation was not changed.

The final Release Candidate must not be described as physically validated or
TestFlight-observed until the two deferred checks are completed.
