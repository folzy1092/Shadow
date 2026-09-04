import Foundation

@main
struct TabBarScrollTests {
    static func main() {
        var count = 0
        func check(_ value: @autoclosure () -> Bool) { precondition(value()); count += 1 }
        var state = TabBarScrollState()
        check(!state.isHidden)
        state.beginGesture()
        state.updateGesture(translation: -100)
        check(!state.isHidden)

        state.configure(mode: .hideOnScroll)
        state.beginGesture()
        state.updateGesture(translation: -19)
        check(!state.isHidden)
        state.updateGesture(translation: -20)
        check(state.isHidden)
        state.updateGesture(translation: -20) // layout echo without finger movement
        check(state.isHidden)
        state.updateGesture(translation: -13)
        check(state.isHidden)
        state.updateGesture(translation: -12)
        check(!state.isHidden)
        state.updateGesture(translation: -31)
        check(!state.isHidden)
        state.updateGesture(translation: -32)
        check(state.isHidden)
        state.endScrolling()
        check(state.isHidden) // persistent mode stays hidden on stop
        state.beginGesture()
        state.updateGesture(translation: 8)
        check(!state.isHidden)

        state.configure(mode: .hideWhileScrolling)
        state.beginGesture()
        state.updateGesture(translation: -20)
        check(state.isHidden)
        state.endScrolling()
        check(!state.isHidden)

        state.beginGesture()
        state.updateGesture(translation: -15)
        state.updateGesture(translation: -14) // reversing direction resets hysteresis
        state.updateGesture(translation: -30)
        check(!state.isHidden)
        state.updateGesture(translation: -34)
        check(state.isHidden)
        state.configure(mode: .alwaysVisible)
        check(!state.isHidden)

        state.configure(mode: .hideOnScroll)
        state.beginGesture()
        state.updateGesture(translation: .nan)
        state.updateGesture(translation: -.infinity)
        check(!state.isHidden)
        state.updateGesture(translation: -20)
        check(state.isHidden)
        state.reset() // foreground, folder change, modal, keyboard, or bottom tap
        check(!state.isHidden)
        state.updateGesture(translation: -100) // resume a gesture after top overscroll
        check(!state.isHidden)
        state.updateGesture(translation: -120)
        check(state.isHidden)
        state.updateGesture(translation: -130, atTop: true)
        check(!state.isHidden) // original modes still reveal at the top

        for direction in [-1.0, 1.0] {
            state.configure(mode: .hideOnAnyScroll)
            state.beginGesture()
            state.updateGesture(translation: 0)
            check(!state.isHidden) // touching without movement is not scrolling
            state.updateGesture(translation: .nan)
            check(!state.isHidden)
            state.updateGesture(translation: direction)
            check(state.isHidden)
            state.updateGesture(translation: -direction * 20)
            check(state.isHidden) // reversing does not reveal
            state.updateGesture(translation: -direction * 20, atTop: true)
            check(state.isHidden) // top-edge bounce / inertia does not reveal
            state.updateGesture(translation: -direction * 20)
            check(state.isHidden) // layout echoes do not change visibility
            state.endScrolling()
            check(!state.isHidden)
            state.beginGesture()
            state.updateGesture(translation: direction, atTop: true)
            check(state.isHidden) // dragging from the very top also hides
            state.reset()
            check(!state.isHidden) // modal / foreground / tab change reset
        }
        check(TabBarScrollMode(rawValue: 3) == .hideOnAnyScroll)
        check(TabBarScrollMode(rawValue: 4) == nil)
        print("Shadow tab bar scrolling: \(count) checks passed")
    }
}
