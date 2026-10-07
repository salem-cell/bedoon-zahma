import Foundation

/// أوزان حساب «احتكاك المرور». كلها قابلة للتعديل عن بُعد (RemoteConfig) — القيم هنا مبدئية فقط.
public struct TrafficScoringWeights: Codable, Hashable, Sendable {
    /// W1: لكل دقيقة تأخير مروري (duration − staticDuration).
    public var delayPerMinute: Double
    /// W2: لكل كيلومتر اختناق (TRAFFIC_JAM) على المسار — أقرب مقياس متاح لـ«الاختناق الشديد».
    public var jamPerKm: Double
    /// W3: لكل كيلومتر بطء (SLOW).
    public var slowPerKm: Double
    /// W4: لكل فاصل اختناق منفصل — مؤشر «توقف وانطلاق» مُستنتج من تقطّع فواصل TRAFFIC_JAM.
    public var stopAndGoPerJamSegment: Double
    /// W5: لكل حادث — Google لا يوفر عدد الحوادث عبر Routes API؛ يبقى الحقل nil والوزن محفوظ لمزوّد مستقبلي.
    public var incidentPenalty: Double
    /// W6: تعقيد المسار — لكل انعطاف، ولكل التفاف (U-turn) إضافي.
    public var turnPenalty: Double
    public var uTurnPenalty: Double
    /// W7: عقوبة المسافة — لكل كيلومتر زيادة عن أقصر الطرق المرشّحة.
    public var extraDistancePerKm: Double
    /// عقوبة لكل تحذير يرجعه Google للمسار (مثل قيود جزئية).
    public var warningPenalty: Double
    /// عقوبة ثابتة عند غياب بيانات المرور (لا نفضّل مسارًا لا نعرف حالته).
    public var missingTrafficDataPenalty: Double
    /// أقصى نسبة التفاف مسموحة لـ«بدون توقف» مقارنة بأسرع طريق (مدة ومسافة).
    public var maxDetourDurationRatio: Double
    public var maxDetourDistanceRatio: Double

    public init(
        delayPerMinute: Double = 5,
        jamPerKm: Double = 10,
        slowPerKm: Double = 3,
        stopAndGoPerJamSegment: Double = 2,
        incidentPenalty: Double = 8,
        turnPenalty: Double = 0.15,
        uTurnPenalty: Double = 2.5,
        extraDistancePerKm: Double = 0.6,
        warningPenalty: Double = 3,
        missingTrafficDataPenalty: Double = 6,
        maxDetourDurationRatio: Double = 1.35,
        maxDetourDistanceRatio: Double = 1.6
    ) {
        self.delayPerMinute = delayPerMinute
        self.jamPerKm = jamPerKm
        self.slowPerKm = slowPerKm
        self.stopAndGoPerJamSegment = stopAndGoPerJamSegment
        self.incidentPenalty = incidentPenalty
        self.turnPenalty = turnPenalty
        self.uTurnPenalty = uTurnPenalty
        self.extraDistancePerKm = extraDistancePerKm
        self.warningPenalty = warningPenalty
        self.missingTrafficDataPenalty = missingTrafficDataPenalty
        self.maxDetourDurationRatio = maxDetourDurationRatio
        self.maxDetourDistanceRatio = maxDetourDistanceRatio
    }

    public static let `default` = TrafficScoringWeights()
}

/// عتبات إعادة التوجيه الديناميكي — قابلة للتعديل من الخادم.
public struct RerouteThresholds: Codable, Hashable, Sendable {
    /// أقل توفير في دقائق التأخير يستحق عرض البديل.
    public var minDelaySavingSeconds: Int
    /// أقصى زيادة مقبولة في المدة الكلية مقابل الانسيابية.
    public var maxExtraDurationSeconds: Int
    /// أقل تحسّن نسبي في درجة الاحتكاك.
    public var minFrictionImprovementRatio: Double
    /// الفاصل الزمني بين فحوصات إعادة الحساب أثناء الرحلة.
    public var checkIntervalSeconds: Int
    /// لا نعرض اقتراحًا جديدًا قبل مرور هذه المدة على آخر اقتراح.
    public var cooldownSeconds: Int

    public init(minDelaySavingSeconds: Int = 180, maxExtraDurationSeconds: Int = 300, minFrictionImprovementRatio: Double = 0.3, checkIntervalSeconds: Int = 90, cooldownSeconds: Int = 240) {
        self.minDelaySavingSeconds = minDelaySavingSeconds
        self.maxExtraDurationSeconds = maxExtraDurationSeconds
        self.minFrictionImprovementRatio = minFrictionImprovementRatio
        self.checkIntervalSeconds = checkIntervalSeconds
        self.cooldownSeconds = cooldownSeconds
    }

    public static let `default` = RerouteThresholds()
}
