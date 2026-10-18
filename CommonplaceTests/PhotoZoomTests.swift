import CoreGraphics
import Testing

@testable import Commonplace

struct PhotoZoomTests {
    // A 3:2 landscape photo fitted on a 400 × 800 portrait screen is 400 × 266.67.
    private let screen = CGSize(width: 400, height: 800)
    private let landscape = CGSize(width: 400, height: 800 / 3)

    @Test func landscapeFitsTheWidth() {
        let fitted = PhotoZoom.fittedSize(CGSize(width: 3000, height: 2000), in: screen)
        #expect(fitted.width == 400)
        #expect(abs(fitted.height - 266.667) < 0.01)
    }

    @Test func portraitFitsTheNarrowerSide() {
        // 2:3 on a 1:2 screen is still limited by the width.
        #expect(
            PhotoZoom.fittedSize(CGSize(width: 2000, height: 3000), in: screen)
                == CGSize(width: 400, height: 600))
        // A tall 1:4 photo is limited by the height.
        #expect(
            PhotoZoom.fittedSize(CGSize(width: 1000, height: 4000), in: screen)
                == CGSize(width: 200, height: 800))
    }

    @Test func smallContentIsCenteredAndLargeContentIsNot() {
        let inset = PhotoZoom.centeringInset(
            content: CGSize(width: 400, height: 200), in: screen)
        #expect(inset == CGSize(width: 0, height: 300))
        let zoomed = PhotoZoom.centeringInset(
            content: CGSize(width: 1000, height: 1600), in: screen)
        #expect(zoomed == .zero)
    }

    @Test func doubleTapAtTheCenterZoomsAroundIt() {
        let content = CGSize(width: 400, height: 800)
        let rect = PhotoZoom.doubleTapRect(
            at: CGPoint(x: 200, y: 400), content: content, bounds: screen)
        #expect(rect == CGRect(x: 120, y: 240, width: 160, height: 320))
    }

    @Test func doubleTapNearAnEdgeStaysInsideTheContent() {
        let content = CGSize(width: 400, height: 800)
        let rect = PhotoZoom.doubleTapRect(
            at: CGPoint(x: 10, y: 400), content: content, bounds: screen)
        #expect(rect == CGRect(x: 0, y: 240, width: 160, height: 320))
    }

    @Test func doubleTapInACornerStaysInsideTheContent() {
        let content = CGSize(width: 400, height: 800)
        let rect = PhotoZoom.doubleTapRect(
            at: CGPoint(x: 395, y: 798), content: content, bounds: screen)
        #expect(rect == CGRect(x: 240, y: 480, width: 160, height: 320))
    }

    @Test func doubleTapOnShortContentCentersVertically() {
        // The rect (320 tall) is taller than the landscape content (266.67), so it centers on it.
        let rect = PhotoZoom.doubleTapRect(
            at: CGPoint(x: 0, y: 0), content: landscape, bounds: screen)
        #expect(rect.origin.x == 0)
        #expect(abs(rect.midY - landscape.height / 2) < 0.001)
        #expect(rect.size == CGSize(width: 160, height: 320))
    }

    @Test func doubleTapRectZoomsToTwoAndAHalf() {
        let rect = PhotoZoom.doubleTapRect(
            at: CGPoint(x: 200, y: 400), content: screen, bounds: screen)
        #expect(screen.width / rect.width == PhotoZoom.doubleTapScale)
    }

    @Test func voiceOverZoomStepsByWholeScales() {
        #expect(PhotoZoom.steppedScale(from: 1, zoomingIn: true) == 2)
        #expect(PhotoZoom.steppedScale(from: 2.5, zoomingIn: true) == 3)
        #expect(PhotoZoom.steppedScale(from: 4, zoomingIn: true) == 4)
        #expect(PhotoZoom.steppedScale(from: 4, zoomingIn: false) == 3)
        #expect(PhotoZoom.steppedScale(from: 2.5, zoomingIn: false) == 2)
        #expect(PhotoZoom.steppedScale(from: 1.2, zoomingIn: false) == 1)
        #expect(PhotoZoom.steppedScale(from: 1, zoomingIn: false) == 1)
    }

    @Test func nearlyFitIsNotZoomed() {
        #expect(!PhotoZoom.isZoomed(1))
        #expect(!PhotoZoom.isZoomed(1.005))
        #expect(PhotoZoom.isZoomed(1.1))
    }
}

struct PhotoViewerStateTests {
    @Test func zoomingSuspendsPagingAndFitRestoresIt() {
        var state = PhotoViewerState(selection: 0)
        #expect(state.isPagingEnabled)
        state.zoomScale = 2.5
        #expect(state.isZoomed)
        #expect(!state.isPagingEnabled)
        state.zoomScale = 1
        #expect(state.isPagingEnabled)
    }

    @Test func changingPhotosResetsZoomAndShowsTheChrome() {
        var state = PhotoViewerState(selection: 2)
        state.zoomScale = 3
        state.toggleChrome()
        #expect(state.isChromeHidden)
        state.selection = 3
        #expect(state.zoomScale == 1)
        #expect(!state.isChromeHidden)
        #expect(state.isPagingEnabled)
    }

    @Test func settingTheSameSelectionKeepsZoomAndChrome() {
        var state = PhotoViewerState(selection: 1)
        state.zoomScale = 2
        state.toggleChrome()
        state.selection = 1
        #expect(state.zoomScale == 2)
        #expect(state.isChromeHidden)
    }

    @Test func singleTapTogglesTheChrome() {
        var state = PhotoViewerState(selection: 0)
        state.toggleChrome()
        #expect(state.isChromeHidden)
        state.toggleChrome()
        #expect(!state.isChromeHidden)
    }
}
