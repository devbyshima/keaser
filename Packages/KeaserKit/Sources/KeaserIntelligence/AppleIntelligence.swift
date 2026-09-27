import Foundation
import FoundationModels
import KeaserKit

/// Whether Apple Intelligence's on-device model can help on this device,
/// and the Keaser features built on it. Everything here runs on the device:
/// Keaser never uses Private Cloud Compute, so nothing a person types leaves
/// their iPhone.
///
/// Safe to call on any system: before iOS 26 (macOS 26) the model does not
/// exist and every answer is "no".
@MainActor
public enum AppleIntelligence {
    /// Whether this device can run the model at all. It may still be turned
    /// off in Settings or downloading; see `isReady`.
    public static var isDeviceEligible: Bool {
        guard #available(iOS 26.0, macOS 26.0, *) else { return false }
        if case .unavailable(.deviceNotEligible) = SystemLanguageModel.default.availability { return false }
        return true
    }

    /// Whether the model can answer now: the device is eligible, Apple
    /// Intelligence is on, the model is downloaded, and it supports the
    /// current language.
    public static var isReady: Bool {
        guard #available(iOS 26.0, macOS 26.0, *) else { return false }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return false }
        return model.supportsLocale()
    }

    /// Smart Suggestions' category model on iOS 26 and later; nil before.
    /// Check `CategoryModel.isReady` before relying on it.
    public static var categoryModel: (any CategoryModel)? {
        guard #available(iOS 26.0, macOS 26.0, *) else { return nil }
        return OnDeviceCategoryModel.shared
    }

    /// Receipt scanning's model on iOS 26 and later; nil before, where the
    /// heuristics read receipts alone.
    public static var receiptModel: (any ReceiptModel)? {
        guard #available(iOS 26.0, macOS 26.0, *) else { return nil }
        return OnDeviceReceiptModel.shared
    }
}
