from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
BAR = (ROOT / 'submodules/TabBarUI/Sources/TabBarController.swift').read_text()
NODE = (ROOT / 'submodules/ChatListUI/Sources/ChatListControllerNode.swift').read_text()
SETTINGS = (ROOT / 'submodules/TelegramCore/Sources/AyuGram/AyuGramSettings.swift').read_text()


class TabBarContracts(unittest.TestCase):
    def test_setting_decodes_old_snapshots_safely(self):
        self.assertIn('decodeIfPresent(Int32.self, forKey: "bottomBarScrollMode") ?? 0', SETTINGS)
        self.assertIn('(0...2).contains(bottomBarScrollMode)', SETTINGS)
        self.assertIn('encode(self.bottomBarScrollMode, forKey: "bottomBarScrollMode")', SETTINGS)

    def test_scroll_requires_registered_current_controller(self):
        self.assertIn('self.currentController === controller && self.scrollSource === controller', BAR)
        root = (ROOT / 'submodules/TelegramUI/Sources/TelegramRootController.swift').read_text()
        self.assertIn('configureScrollVisibility(source: chatListController, mode: settings.bottomBarScrollMode)', root)

    def test_motion_comes_from_gesture_not_layout_offset(self):
        self.assertIn('panGestureRecognizer.translation(in: listView.view).y', NODE)
        self.assertIn('else if listView.isTracking', NODE)
        self.assertIn('isPrimary && self.inlineStackContainerNode == nil', NODE)

    def test_manual_hiding_is_separate(self):
        self.assertIn('self.explicitlyHidden || self.scrollState.isHidden', BAR)
        self.assertIn('self.explicitlyHidden = value', BAR)

    def test_transition_and_lifecycle_reset(self):
        self.assertIn('duration: 0.22', BAR)
        self.assertIn('UIAccessibility.isReduceMotionEnabled', BAR)
        for name in ['willResignActiveNotification', 'didBecomeActiveNotification', 'keyboardWillShowNotification']:
            self.assertIn(name, BAR)
        self.assertIn('NotificationCenter.default.removeObserver(observer)', BAR)

    def test_existing_visibility_cache_still_used(self):
        geometry = (ROOT / 'submodules/TabBarUI/Sources/TabBarContollerNode.swift').read_text()
        self.assertIn('isTabBarHidden: self.tabBarHidden', geometry)
        self.assertIn('let isTabBarHidden: Bool', geometry)
        self.assertIn('guard self.tabBarControllerNode.tabBarHidden != hidden else { return }', BAR)

    def test_runtime_model_not_persisted(self):
        model = (ROOT / 'submodules/Display/Source/TabBarScrollState.swift').read_text()
        for token in ['UIKit', 'UserDefaults', 'Postbox', 'frame', 'setControllers']:
            self.assertNotIn(token, model.replace('independent of UIKit animation', 'independent of animation'))


if __name__ == '__main__':
    unittest.main()
