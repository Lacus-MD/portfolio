import SwiftUI

/// A kezdőképernyő platformkártyája. A geometria (36-os sugár, 52-es gyűrű,
/// 26-os oszlopköz) az eredeti tervből jön; a felület pasztell alapszínt és
/// lokalizált jobb felső sarokátmenetet kap.
struct PlatformCard: View {
    let summary: PlatformSummary
    var animateRing: Bool = true
    var isFeatured: Bool = false

    private var palette: PlatformCardPalette {
        .resolve(for: summary.platform, featured: isFeatured)
    }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                DonutRing(progress: summary.share,
                          track: palette.ringTrack,
                          arc: palette.accent,
                          animate: animateRing)
                accountGlyph
            }
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(summary.platform.name)
                        .font(DS.cardTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer(minLength: 4)
                    statusBadge
                }

                // A platform MAI ÉRTÉKE. Eddig csak a Platformok fülön
                // szerepelt; a kártyán a befizetés és a hozam állt, amiből
                // a mostani egyenleg csak fejben jött ki.
                Text(summary.isMissingValue ? "—" : Fmt.huf(abs(summary.valueHUF)))
                    .font(DS.font(21, .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 1)

                HStack(alignment: .top, spacing: 26) {
                    if summary.platform.isLiability {
                        // Tartozásnál nincs befizetés és nincs hozam. Ami van:
                        // mennyivel tartozol — pozitív számként kiírva, mert a
                        // „−650 867 Ft tartozás" kétszeres tagadás.
                        stat("Tartozás", Fmt.huf(abs(summary.valueHUF)), alpha: 0.72)
                    } else if summary.platform.isTransactional {
                        // Folyószámlán a hozam értelmetlen: ide a fizetés
                        // érkezik és innen költesz. Ami érdekes, az az, hogy
                        // mennyi van rajta MOST — az pedig fent áll nagyban.
                        stat("Folyószámla", "egyenleg", alpha: 0.6)
                    } else {
                        stat("Befizetés", Fmt.huf(summary.depositsHUF), alpha: 0.72)
                        if summary.isMissingValue {
                            stat("Hozam", "hiányzó adat", alpha: 0.6)
                        } else {
                            // A százalék mellett a FORINTOS összeg is: „+0,87%"
                            // önmagában nem mondja meg, mennyi az a pénzben.
                            stat("Hozam",
                                 "\(Fmt.percent(summary.gainPct))  ·  \((summary.gainHUF >= 0 ? "+" : "") + Fmt.huf(summary.gainHUF))",
                                 alpha: 0.6)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .foregroundStyle(palette.ink)
        .background {
            cardSurface
        }
        .contentShape(.rect(cornerRadius: DS.R.platformCard))
    }

    private func stat(_ label: String, _ value: String, alpha: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(DS.font(10.5, .regular)).opacity(alpha)
            Text(value).font(DS.font(13.5, .medium))
        }
    }

    private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: DS.R.platformCard, style: .continuous)
        return shape
            .fill(palette.baseColors.first ?? .clear)
            .shadow(color: palette.shadow, radius: 10, x: 0, y: 5)
            .overlay {
                shape.fill(
                    LinearGradient(colors: palette.baseColors,
                                   startPoint: .leading, endPoint: .trailing)
                )
            }
            .overlay {
                shape.fill(
                    RadialGradient(
                        colors: [
                            palette.cornerColors[0].opacity(isFeatured ? 0.78 : 0.42),
                            palette.cornerColors[1].opacity(isFeatured ? 0.40 : 0.18),
                            .clear
                        ],
                        center: UnitPoint(x: 0.98, y: 0.04),
                        startRadius: 0,
                        endRadius: 170
                    )
                )
            }
    }

    @ViewBuilder private var accountGlyph: some View {
        let platform = summary.platform
        if platform.kind == .current,
           platform.name.localizedCaseInsensitiveContains("revolut") {
            Text(String(platform.monogram.prefix(1)))
                .font(DS.font(17, .bold))
                .italic()
                .foregroundStyle(palette.accent)
        } else {
            Image(systemName: glyphName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
        }
    }

    private var glyphName: String {
        switch summary.platform.kind {
        case .brokerage: "chart.bar.fill"
        case .savings:   "piggybank.fill"
        case .current:   "wallet.bifold.fill"
        case .credit:    "creditcard.fill"
        }
    }

    @ViewBuilder private var statusBadge: some View {
        if isFeatured && summary.platform.hasMeaningfulGain && !summary.isMissingValue {
            badge {
                Image(systemName: summary.gainPct < 0 ? "arrow.down.right" : "arrow.up.right")
                Text(Fmt.percent(summary.gainPct))
            }
        } else if summary.platform.isLiability {
            badge {
                Circle().fill(palette.accent).frame(width: 5, height: 5)
                Text("Tartozás")
            }
        } else if summary.platform.isTransactional {
            badge { Text("Folyószámla") }
        } else if summary.platform.kind == .savings {
            Circle()
                .fill(palette.accent)
                .frame(width: 5, height: 5)
                .padding(10)
                .background(palette.badgeFill, in: .rect(cornerRadius: 11))
        }
    }

    private func badge<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 5) { content() }
            .font(DS.badge)
            .foregroundStyle(summary.platform.isLiability ? palette.accent : palette.ink.opacity(0.88))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(palette.badgeFill, in: .rect(cornerRadius: 11))
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// A kártya fánkgyűrűje. A handoff geometriája: r=24 egy 60-as nézetdobozban,
/// 4 vastag, kerek végű vonal, −90 fokkal forgatva, hogy fent kezdjen.
struct DonutRing: View {
    let progress: Double
    let track: Color
    let arc: Color
    var animate: Bool = true

    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(track, style: .init(lineWidth: 4, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(0.001, min(shown, 1)))
                .stroke(arc, style: .init(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(2)
        .onAppear {
            guard animate else { shown = progress; return }
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.3).delay(0.35)) {
                shown = progress
            }
        }
        .onChange(of: progress) { _, new in
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.6)) { shown = new }
        }
    }
}
