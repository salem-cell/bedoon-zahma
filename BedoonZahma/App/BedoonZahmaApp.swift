import Features
import GoogleMaps
import GoogleNavigation
import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // مفتاح iOS مقيّد بـ Bundle ID — يخدم Maps SDK وNavigation SDK فقط (Places/Routes عبر الخادم).
        if let key = AppConfig.googleMapsIOSKey, !key.isEmpty {
            GMSServices.provideAPIKey(key)
        } else if !AppConfig.useMocks {
            assertionFailure("GOOGLE_MAPS_IOS_KEY مفقود — راجع Config/Secrets.xcconfig")
        }
        return true
    }
}

@main
struct BedoonZahmaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var env = AppContainer.makeEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView(env: env)
        }
    }
}
