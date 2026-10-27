"""Source-level regression checks for entering a chat: the title bubble's glass and the screen corners.

Run from the repository root:
    python3 -m unittest discover -s Tests/ShadowVisualSettings -v

These checks do not compile Swift or exercise UIKit. Set SHADOW_TEST_REVISION to
inspect a Git revision instead of the working tree (useful as a negative control).
"""

import unittest

from test_source_contracts import read_source, section


NAVIGATION_BAR = "submodules/TelegramUI/Components/NavigationBarNode/Sources/NavigationBarNode.swift"
COORDINATOR = "submodules/Display/Source/NavigationTransitionCoordinator.swift"


class ShadowChatEntryContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bar = read_source(NAVIGATION_BAR)
        cls.coordinator = read_source(COORDINATOR)

    def test_bar_readapts_glass_when_the_transition_hands_it_over(self):
        body = section(self.bar, "private func applyGlassVisibility() {", "\n    }\n")
        unhide = body.index("titleView.isGlassPillDetached = detached && self.transitionTitlePill != nil")
        readapt = body.index("self.readaptGlassOnHandover()")
        self.assertLess(unhide, readapt)
        self.assertIn("if wasDetached && !detached {", body)
        handover = section(self.bar, "private func readaptGlassOnHandover() {", "\n    }\n")
        self.assertIn("self.glassReadaptationGeneration += 1", handover)
        self.assertIn("self.readaptGlass()", handover)
        self.assertNotIn("asyncAfter", handover)

    def test_entering_hierarchy_does_not_readapt_on_a_timer(self):
        body = section(self.bar, "func enteredHierarchy() {", "\n    }")
        self.assertNotIn("readaptGlass", body)

    def test_header_capsule_pressed_by_a_hold_gets_new_glass_when_detached(self):
        bar = read_source("submodules/TelegramUI/Components/NavigationBarComponent/Sources/NavigationBarComponent.swift")
        detach = section(bar, "public var plattersDetached: Bool = false {", "self.applyPlattersDetached()")
        sampled = detach.index("self.detachedRightPressScales = zip(rightScales, barRightPresses)")
        renew = detach.index("self.renewGlassPressedAtDetach()")
        self.assertLess(sampled, renew)
        body = section(bar, "private func renewGlassPressedAtDetach() {", "\n        }\n\n")
        self.assertIn("navigationBarCapsulePress(container).isPressed || hasActiveTouch(container)", body)
        self.assertIn("container.renewGlass()", body)
        self.assertIn("self.isLeftCapsuleLent", body)

    def test_progress_run_schedules_corner_restore_on_arrival(self):
        run = section(self.coordinator, "private func runProgressCurve(", "\n    }")
        install = run.index("self.installProgressKeyframes(curve: curve, timing: timing)")
        arrival = run.index("self.scheduleCornersRestoreOnArrival(curve: curve, timing: timing)")
        self.assertLess(install, arrival)

    def test_corner_restore_runs_on_the_clock_when_the_card_is_in_place(self):
        body = section(self.coordinator, "private func scheduleCornersRestoreOnArrival(", "\n    }\n")
        self.assertIn("arrivedCardTolerance", body)
        self.assertIn("timing.sampleTimes.reversed()", body)
        self.assertIn("curve.value(at: time) - curve.target", body)
        self.assertIn("self.clock.schedule(atAnimationTime: arrival", body)
        self.assertIn("self?.restoreTopNodeCorners()", body)
        self.assertNotIn("DispatchQueue", body)
        self.assertRegex(self.coordinator, r"private static let arrivedCardTolerance: CGFloat = 0\.5\b")

    def test_corner_restore_is_idempotent(self):
        body = section(self.coordinator, "private func restoreTopNodeCorners() {", "\n    }\n")
        self.assertIn("guard let (clipsToBounds, cornerRadius, usesCornerRadii) = parameters else {", body)
        self.assertIn("self.topNodeInitialParameters = nil", body)
        self.assertIn("self.bottomNodeInitialParameters = nil", body)


if __name__ == "__main__":
    unittest.main()
