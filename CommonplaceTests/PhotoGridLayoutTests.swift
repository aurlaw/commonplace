import CoreGraphics
import Testing

@testable import Commonplace

struct PhotoGridLayoutTests {
    private let layout = PhotoGridLayout(rowHeight: 100, spacing: 2)

    @Test func noTilesHaveNoFrames() {
        #expect(layout.frames(count: 0, width: 302).isEmpty)
    }

    @Test func oneTileFillsTheWidth() {
        #expect(
            layout.frames(count: 1, width: 302) == [CGRect(x: 0, y: 0, width: 302, height: 202)])
    }

    @Test func twoTilesSplitTheWidth() {
        #expect(
            layout.frames(count: 2, width: 302) == [
                CGRect(x: 0, y: 0, width: 150, height: 202),
                CGRect(x: 152, y: 0, width: 150, height: 202),
            ]
        )
    }

    @Test func sixTilesUseAHeroAndFiveSmallerTiles() {
        #expect(
            layout.frames(count: 6, width: 304) == [
                CGRect(x: 0, y: 0, width: 202, height: 202),
                CGRect(x: 204, y: 0, width: 100, height: 100),
                CGRect(x: 204, y: 102, width: 100, height: 100),
                CGRect(x: 0, y: 204, width: 100, height: 100),
                CGRect(x: 102, y: 204, width: 100, height: 100),
                CGRect(x: 204, y: 204, width: 100, height: 100),
            ]
        )
    }
}
