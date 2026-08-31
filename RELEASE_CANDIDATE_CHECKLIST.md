# Portfolio 1.0 Release Candidate checklist — Build 30

This checklist is the no-device verification path for Build 30. It is safe to
run without bank credentials, signing secrets, or a connected phone.

- [x] XcodeGen regenerated `Portfolio.xcodeproj` from `project.yml`.
- [x] Unit-test target compiles for iPhoneOS without signing.
- [x] All app, widget, share-extension, watch app, and watch widget targets
  compile in the Release configuration with signing disabled for this
  no-device pass.
- [x] Build number is read from the generated app bundle Info.plist.
- [x] iCloud sync envelope round-trip and revision conflict tests compile in
  the iPhoneOS unit-test target.
- [x] The app pulls remote portfolio revisions on startup/foreground and
  publishes successful local saves to the existing iCloud Documents container.
- [x] Lightyear fractional quantities with three or more decimal places are
  parsed as decimals rather than thousands-separated integers.
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

The final Release Candidate must not be described as physically validated or
TestFlight-observed until the two deferred checks are completed.
