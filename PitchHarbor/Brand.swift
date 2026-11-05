// Shared product identity and reusable brand lockup.
// Keep export filenames here so sharing surfaces use the same public name.

import SwiftUI

enum Brand {
    static let name = "PitchHarbor"
    static let tagline = "Your Team. Every Moment."
    static let backupFilename = "PitchHarbor-backup"
    static let boardFilename = "PitchHarbor-board.png"
}

struct BrandLockup: View {
    var showsTagline = false
    var body: some View {
        HStack(spacing: 10) {
            Image("BrandIcon").resizable().interpolation(.high)
                .frame(width: showsTagline ? 48 : 36, height: showsTagline ? 48 : 36)
                .clipShape(RoundedRectangle(cornerRadius: showsTagline ? 12 : 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(Brand.name).font(.system(.title3, design: .rounded, weight: .bold))
                if showsTagline { Text(Brand.tagline).font(.caption).foregroundStyle(Palette.secondaryText) }
            }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("brandLockup")
    }
}
