# Performance baseline

Build 25 keeps the existing scroll regression suite and adds signposts around
the two long-running paths that previously competed with scrolling:

- `Portfolio Refresh` — network, quote aggregation, and snapshot preparation.
- `News Load` — feed/mover loading, image prefetch scheduling, and the final fade.

The existing `AppUITests/ScrollPerformanceTests.swift` suite measures the
system scroll-deceleration metric for the four main tabs, the portfolio chart,
and settled settings scrolling. Run it on a simulator or device with:

```zsh
xcodebuild test -project Portfolio.xcodeproj -scheme Portfolio \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PortfolioUITests/ScrollPerformanceTests
```

The physical phone was unavailable during this stabilization pass, so no
numeric before/after claim is made here. The release gate remains: no
reproducible user-visible hitch over 100 ms and no more than 10% regression
against the first captured baseline.
