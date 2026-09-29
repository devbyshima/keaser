import SwiftUI
import WidgetKit

@main
struct KeaserWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SpendingWidget()
        AddExpenseControl()
        ScanReceiptControl()
    }
}
