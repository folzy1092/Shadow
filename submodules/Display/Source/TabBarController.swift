import Foundation
import UIKit
import AsyncDisplayKit
import SwiftSignalKit

public enum TabBarItemSwipeDirection {
    case left
    case right
}

public protocol TabBarController: ViewController {
    var currentController: ViewController? { get }
    var controllers: [ViewController] { get }
    var selectedIndex: Int { get set }
    
    func setControllers(_ controllers: [ViewController], selectedIndex: Int?)
    
    func updateBackgroundAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition)
    
    func frameForControllerTab(controller: ViewController) -> CGRect?
    func isPointInsideContentArea(point: CGPoint) -> Bool
    
    func updateIsTabBarEnabled(_ value: Bool, transition: ContainedViewLayoutTransition)
    func updateIsTabBarHidden(_ value: Bool, transition: ContainedViewLayoutTransition)
    func updateLayout(transition: ContainedViewLayoutTransition)
    
    func updateControllerLayout(controller: ViewController)
    func tabBarScrollBegan(from controller: ViewController)
    func tabBarScrollChanged(translation: CGFloat, from controller: ViewController)
    func tabBarScrollEnded(from controller: ViewController)
    func revealScrollingTabBar(from controller: ViewController)
}

// Other tab bar implementations can retain their existing behavior.
public extension TabBarController {
    func tabBarScrollBegan(from controller: ViewController) {}
    func tabBarScrollChanged(translation: CGFloat, from controller: ViewController) {}
    func tabBarScrollEnded(from controller: ViewController) {}
    func revealScrollingTabBar(from controller: ViewController) {}
}
