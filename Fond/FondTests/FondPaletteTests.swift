import Testing
@testable import Fond

struct FondPaletteTests {
    @Test func exactPaletteValues() {
        #expect(FondPalette.fieldLight.hex == 0xEEE7DC)
        #expect(FondPalette.fieldDark.hex == 0x191715)
        #expect(FondPalette.keepsakeLight.hex == 0xFFF9EE)
        #expect(FondPalette.keepsakeDark.hex == 0x24201C)
        #expect(FondPalette.amberLight.hex == 0xA85F00)
        #expect(FondPalette.amberDark.hex == 0xD68A1F)
    }

    @Test func textContrastMeetsAA() {
        #expect(FondRGB.contrast(FondPalette.inkDark, FondPalette.keepsakeDark) >= 4.5)
        #expect(FondRGB.contrast(FondPalette.inkLight, FondPalette.keepsakeLight) >= 4.5)
        #expect(FondRGB.contrast(FondPalette.inkSecondaryDark, FondPalette.keepsakeDark) >= 4.5)
        #expect(FondRGB.contrast(FondPalette.inkSecondaryLight, FondPalette.keepsakeLight) >= 4.5)
        #expect(FondRGB.contrast(FondPalette.amberDark, FondPalette.keepsakeDark) >= 4.5)
        #expect(FondRGB.contrast(FondPalette.amberLight, FondPalette.keepsakeLight) >= 4.5)
    }

    @Test func controlContrastSurvivesMaterialChanges() {
        #expect(FondRGB.contrast(FondPalette.inkDark, FondPalette.controlPlateDark) >= 4.5)
        #expect(FondRGB.contrast(FondPalette.inkLight, FondPalette.controlPlateLight) >= 4.5)
        #expect(FondRGB.contrast(FondPalette.sendForegroundDark, FondPalette.amberDark) >= 4.5)
        #expect(FondRGB.contrast(FondPalette.sendForegroundLight, FondPalette.amberLight) >= 4.5)
    }
}
