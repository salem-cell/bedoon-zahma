import DesignSystem
import Features
import GoogleMaps
import GoogleNavigation
import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // خط الهوية «مشوارك أسهل» (Noto Kufi Arabic) إن كان مضمّنًا في الحزمة، وإلا خط النظام.
        if UIFont(name: "NotoKufiArabic", size: 12) != nil || UIFont.familyNames.contains("Noto Kufi Arabic") {
            BZFont.family = "Noto Kufi Arabic"
        }
        // مفتاح iOS مقيّد بـ Bundle ID — يخدم Maps SDK وNavigation SDK فقط (Places/Routes عبر الخادم).
        if let key = AppConfig.googleMapsIOSKey, !key.isEmpty {
            GMSServices.provideAPIKey(key)
        } else if !AppConfig.useMocks {
            // لا نهيّئ SDK بلا مفتاح؛ AppContainer يتحوّل إلى خريطة محايدة وملاحة معطّلة بخطأ واضح.
            NSLog("[BedoonZahma] GOOGLE_MAPS_IOS_KEY مفقود — الخرائط والملاحة معطّلة في هذا البناء")
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
