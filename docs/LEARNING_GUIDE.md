# Học iOS qua source code này (dành cho người từ Flutter)

Mục tiêu: **bắt đầu bằng SwiftUI để tận dụng tư duy Flutter**, rồi **lấp ngay các lỗ hổng native** (UIKit, lifecycle, persistence, networking, memory, testing) để tiến tới level Senior iOS/Mobile.

| Phần | Nội dung | Cách học | Thời lượng gợi ý |
|---|---|---|---|
| **A. SwiftUI qua tư duy Flutter** | Swift, state, rendering và layout, điều hướng, concurrency | Đọc code có sẵn và làm bài tập nhỏ | 4–5 tuần |
| **B. Nền tảng native** | UIKit và lifecycle, SwiftData ↔ CoreData, networking, memory/performance, testing | **Bài lab** sửa và mở rộng chính app này | 6–8 tuần |
| **C. Lên Senior** | Kiến trúc, bảo mật và tích hợp hệ thống, build và phát hành | Làm các mục trong `docs/ROADMAP.md` | Liên tục, học trong lúc làm dự án |

Cách dùng: mỗi bài chỉ ra *đọc file nào*, *cần nắm gì*, *tương đương bên Flutter* và *bài tập/lab*. Phần B nói rõ chỗ nào **code chưa có** (app này chỉ dùng SwiftUI và chạy offline), khi đó lab sẽ hướng dẫn tự thêm vào. Đọc kèm `docs/ARCHITECTURE.md` để hiểu lý do thiết kế.

---

## 0. Bản đồ Flutter → iOS

| Flutter | iOS (trong repo này) | Khác biệt quan trọng |
|---|---|---|
| `Widget`, `build()` | `struct … : View`, `var body` | View là **struct giá trị**, bị tạo lại liên tục và rất rẻ. Không giữ state trong thuộc tính thường. |
| `Key` | Identity: vị trí trong cây, `ForEach(id:)`, `.id()` | Xem A4.2. |
| Constraints đi xuống, size đi lên | Proposal → size → placement | Gần như giống hệt; khác ở chỗ view có thể **bỏ qua** proposal (xem A4.2). |
| `StatefulWidget` + `setState` | `@State` | Không có `setState`: gán giá trị mới là UI tự vẽ lại. |
| Truyền callback `onChanged` / `TextEditingController` | `@Binding` (`$text`) | Binding là "con trỏ hai chiều" tới state của view cha. |
| `ChangeNotifier` / Riverpod `Notifier` | `@Observable class` | **Không có `notifyListeners()`.** SwiftUI tự theo dõi thuộc tính nào được *đọc* trong `body`. |
| `Provider` / `InheritedWidget` | `@Environment` | Ở đây chỉ có một dependency dùng chung là `AppContainer`. |
| `FutureBuilder` / `initState` gọi async | `.task { }` / `.task(id:)` | Tự huỷ khi view biến mất; `id` đổi thì chạy lại. |
| `dispose()` | `.onDisappear`, `deinit`, huỷ `Task` | Nhớ là ARC không có GC dọn vòng tham chiếu (xem B4). |
| `StreamBuilder` trên database | `@Query` (SwiftData) | Query tự cập nhật khi dữ liệu đổi. |
| sqflite / Drift / Isar | SwiftData `@Model` (chạy trên nền CoreData) | Model là **class** và tự observable. |
| `json_serializable` / `freezed` | `Codable`, struct `Equatable` | Swift tự sinh code, không cần build_runner. |
| `http` / Dio | `URLSession` + `async/await` | Xem B3. |
| `Navigator 2.0` / GoRouter | `NavigationStack(path:)` + `navigationDestination(for:)` | Route là giá trị `Hashable`. |
| `showModalBottomSheet` / `showDialog` | `.sheet`, `.confirmationDialog`, `.alert` | Điều khiển bằng state, không gọi hàm imperatively. |
| Implicit animation / `AnimatedSwitcher` | `withAnimation`, `.animation(_:value:)`, `.transition` | Xem A6. |
| `PlatformView` / `MethodChannel` | `UIViewRepresentable` / gọi API native trực tiếp | Không cần "channel": Swift **chính là** ngôn ngữ native. |
| `WidgetsBindingObserver` | `scenePhase`, `UIApplicationDelegate` | Xem B1. |
| `ThemeData` | Token trong `DesignSystem/` + control hệ thống | iOS ưu tiên control gốc của hệ thống. |
| `flutter_bloc` | `enum Step` trong `RestoreFlowModel`, `ImportFlowModel` | Enum có associated value thay cho class state. |
| Isolate | `actor`, `@MainActor`, `Sendable` | Swift 6 kiểm tra data race **lúc biên dịch**. |
| `pubspec.yaml` | Swift Package (`Packages/FinanceKit/Package.swift`) | Compiler giữ ranh giới giữa các module. |
| `flutter test` / `integration_test` | Swift Testing, XCTest, XCUITest | Xem B5. |
| DevTools | Instruments, Memory Graph, LLDB | Xem B4. |
| Hot reload | `#Preview` | Mỗi màn hình có preview với dữ liệu mẫu. |

**Ba khác biệt dễ vấp nhất:**
1. Identity của view quyết định khi nào `@State` bị reset.
2. Thứ tự modifier có ý nghĩa.
3. `struct` là kiểu giá trị (bị copy), `class` là kiểu tham chiếu (dùng chung, và có thể leak).

---

# Phần A — SwiftUI qua tư duy Flutter

## A1. Chuẩn bị (nửa ngày)

1. Mở `PersonalFinance.xcodeproj` và chạy app trên simulator.
2. Mở `Features/Home/HomeView.swift`, bật Canvas (⌥⌘↩) và xem preview *New user* và *With data*.
3. Chạy `cd Packages/FinanceKit && swift test`.
4. Lướt `README.md` và phần *Modules* trong `docs/ARCHITECTURE.md`.
5. Làm quen Xcode: ⌘B build, ⌘R chạy, ⌘U test, ⇧⌘O mở nhanh file, ⌃⌘ click để nhảy tới định nghĩa, breakpoint, Debug Navigator.

```
FinanceDomain       Swift thuần: tiền, quy tắc, lịch, backup/CSV   ← học Swift
FinancePersistence  SwiftData: model, schema, service              ← học dữ liệu
FinanceFeatures     @Observable view model, AppRouter              ← học state
PersonalFinance/    SwiftUI view, app lifecycle                    ← học UI
```

## A2. Swift cơ bản qua FinanceDomain (1–2 ngày)

| File | Học gì | Tương đương Dart |
|---|---|---|
| `FinanceDomain/Money.swift` | `struct`, `Equatable`, `throws`, `guard`, `Int64` cho tiền | class bất biến + `==` |
| `FinanceDomain/AccountTypes.swift` | `enum` có `rawValue`, `CaseIterable`, `switch` phải đủ case | enhanced enum |
| `FinanceDomain/LedgerValidationError.swift` | Error là `enum`, `LocalizedError` | `sealed class` exception |
| `FinanceDomain/CurrencyDefinition.swift` | `static`, `extension`, optional (`?`, `if let`, `??`) | null safety |
| `FinanceDomain/RecurrenceRules.swift` | Hàm thuần, `Calendar`, `Date` | — |
| `Tests/FinanceDomainTests/MoneyTests.swift` | `@Test`, `#expect`, `#expect(throws:)` | `test()`, `expect()` |

**Bài tập:** viết `Money.isGreater(than:)` và test cho nó.

## A3. Swift nâng cao cho SwiftUI (2 ngày)

Phần lớn lỗi biên dịch "khó hiểu" của người mới nằm ở đây.

| Khái niệm | Xem ở đâu | Cần nắm |
|---|---|---|
| `some View` (opaque type), `any P` (existential) | `body` của mọi view | `some` = "một kiểu cụ thể, compiler biết, người gọi không biết". Lỗi *"return statements do not have matching underlying types"* → dùng `@ViewBuilder`, `Group` hoặc tách view. Tránh `AnyView` (xem A4.2). |
| Result builder | `AppScreen.destination` (`@ViewBuilder`) trong `Support/NavigationDestinations.swift`; `switch` trong `RestoreReviewView` (`Features/Backup/BackupView.swift`) | `body` không phải hàm bình thường: mỗi dòng là một view được gom lại. Vì thế không viết được `let x = 1; print(x)` tuỳ ý trong đó. |
| Protocol và generics | `View`, `ViewModifier` (`CardStyle`), `FileDocument` (`ExportFile` trong `BackupFiles.swift`), `AppRouter.open<Value: Hashable>`, `plainNumber` trong `TransactionCSVImport.swift` (`<S: StringProtocol>`) | Lập trình hướng protocol: protocol + extension thay cho class kế thừa. |
| Property wrapper | `@State`, `@Binding`, `@AppStorage` | `@State var x` sinh ra `_x` (storage, nằm ngoài struct) và `$x` (projected value = `Binding`). Lưu ý: macro `@Observable` không dùng chung được với property wrapper trên stored property. |
| Macro | `@Observable`, `@Model`, `#Predicate`, `#Preview` | Chuột phải › *Expand Macro* để xem code được sinh ra. |
| Closure | `RestoreFlowModel(restore:makeSafetyCopy:)`, `Binding(get:set:)` | `@escaping`, capture list `[weak self]` (xem B4), trailing closure. |
| Key path | `\Wallet.sortOrder`, `\.self`, `$model.amountText` | Giống tham chiếu tới một thuộc tính dạng giá trị; `@Bindable` dùng key path để tạo binding. |
| `Codable` | `FinanceDomain/Backup.swift`, `BackupCodec` (chiến lược mã hoá ngày tuỳ chỉnh) | Giống `json_serializable` nhưng compiler tự sinh. |

**Lab A3:** viết property wrapper `@Clamped(0...365) var interval` trong một file test, có `wrappedValue` và `projectedValue`, kèm 3 test. Sau bài này, cách `@State` hoạt động sẽ không còn là "phép màu".

## A4. Hành trình state management (và nền tảng rendering)

### A4.1 View thuần, chưa có state: DesignSystem (nửa ngày)

| File | Học gì |
|---|---|
| `DesignSystem/Components/IconBadge.swift` | View nhỏ nhất |
| `DesignSystem/Components/MoneyText.swift` | Tham số enum, computed property, accessibility label |
| `DesignSystem/Components/CardStyle.swift` | `ViewModifier` + `extension View` |
| `DesignSystem/Metrics.swift`, `AppColor.swift` | Design token |

**Bài tập:** component `TagChip(text:)` có `#Preview`.

### A4.2 Rendering, Identity & Layout (1–2 ngày)

Học **trước** `@State`, vì thời gian sống của state phụ thuộc vào identity.

**Rendering: view được vẽ lại thế nào**
- Mỗi lần dependency đổi, SwiftUI gọi lại `body` để tạo cây view mới (rất rẻ), so sánh với cây cũ, rồi chỉ cập nhật phần khác.
- Dependency của một `body` gồm: `@State`, `@Binding`, thuộc tính `@Observable` được **đọc**, `@Environment`, `@Query`.
- Xem `body` chạy khi nào: thêm `let _ = Self._printChanges()` vào đầu `body` của `HomeView`, rồi thêm một giao dịch và đọc console.

**Identity: SwiftUI nhận ra "cùng một view" thế nào**

| Loại | Ví dụ trong code | Hệ quả |
|---|---|---|
| Theo cấu trúc (vị trí trong cây) | `RecurringDetailView`: `if recurring.isDeleted { Color.clear } else { content }` | Hai nhánh là **hai view khác nhau**; đổi nhánh thì state của nhánh cũ bị huỷ. |
| Tường minh trong `ForEach` | `ForEach(wallets)` (model `Identifiable`), so với `ForEach(items.indices, id: \.self)` trong `HomeView` (thẻ *Upcoming*) và `BackupView` | Dùng **chỉ số** làm id chỉ ổn khi danh sách không đổi. Danh sách thay đổi thì state và animation sẽ gắn nhầm phần tử. |
| Tường minh bằng `.id(x)` | (chưa dùng) | `x` đổi = view mới hoàn toàn, mọi `@State` bên trong bị reset. |

- **`if` khác modifier ternary:** `if hidden { … }` huỷ view; `.opacity(hidden ? 0 : 1)` giữ nguyên identity và state.
- **Tránh `AnyView`:** nó xoá thông tin kiểu, nên SwiftUI khó so sánh cây. Dùng `@ViewBuilder` hoặc `Group`.

**Layout: proposal → size → placement**
1. View cha **đề xuất** (propose) kích thước cho view con. Đề xuất có thể là `nil`, nghĩa là "cho tôi kích thước lý tưởng của bạn".
2. View con **tự chọn** kích thước, và có thể bỏ qua đề xuất. Ví dụ `Text` chỉ lấy vừa chữ.
3. View cha **đặt vị trí** cho view con.

So với Flutter thì gần như giống, nhưng **không có lỗi "unbounded constraints"**: view chỉ lấy kích thước lý tưởng của nó.

| Flutter | SwiftUI | Xem ở đâu |
|---|---|---|
| `Expanded` / `SizedBox.expand` | `.frame(maxWidth: .infinity)`, `Spacer()` | Nút "Add Transaction" trong `HomeView` |
| `Flexible(flex:)` | `.layoutPriority(_:)` | (lab bên dưới) |
| `IntrinsicWidth` | `.fixedSize()` | — |
| `LayoutBuilder` | `GeometryReader` (lấy **toàn bộ** chỗ được đề xuất, dễ làm vỡ layout) | `BreakdownList` trong `DesignSystem/Charts/ChartComponents.swift` |
| `GridView` | `LazyVGrid`, `Grid` | `DesignSystem/Components/AppearancePickers.swift` |
| `ListView.builder` | `List`, `LazyVStack` (lazy); `VStack` trong `ScrollView` là **không lazy** | `TransactionListView` (`List`) và `HomeView` (`ScrollView` + `VStack`) |
| `CustomMultiChildLayout` | `Layout` protocol, `ViewThatFits` | (lab bên dưới) |

**Thứ tự modifier:** mỗi modifier bọc view thành một view mới, nên `.padding().background(.red)` tô màu cả phần padding, còn `.background(.red).padding()` thì không.

**Labs A4.2**
1. **Identity:** bọc nội dung `ReportsView` bằng `.id(app.dataVersion)`. Đổi kỳ báo cáo, rồi thêm một giao dịch. Kỳ vừa chọn bị mất vì `ReportsModel` (giữ trong `@State`) bị tạo lại. Gỡ `.id` ra và giải thích lý do.
2. **ForEach:** sửa thẻ *Upcoming* trong `HomeView` để dùng id ổn định (`"\(recurring.id)-\(occurrence.day.rawValue)"`) thay cho `indices`.
3. **Layout:** với cỡ chữ trợ năng lớn nhất, giữ số tiền trong hàng ví không bị cắt (`layoutPriority`). Đổi thẻ dòng tiền 3 cột trong `DashboardSections` sang `ViewThatFits`, để tự xếp dọc khi không đủ chỗ.

### A4.3 `@State` và `@Binding`: state cục bộ (1 ngày)

| Đọc theo thứ tự | Vì sao |
|---|---|
| `DesignSystem/Components/AmountField.swift` | `@Binding`: view con không sở hữu state; preview dùng `@Previewable @State` |
| `DesignSystem/Components/PeriodPicker.swift` | `@Binding` của cha kết hợp `@State` riêng |
| `Features/Categories/CategoryFormView.swift` | Form chỉ dùng `@State`, `didLoad`, `@State error` → alert |
| `Features/Transactions/CategoryPickerView.swift` | `@Binding selection` trả kết quả về cha |
| `Features/More/NotificationSettingsView.swift` | `@AppStorage` (giống `shared_preferences`) |

**Cần nắm:** `@State` luôn `private` và sống theo identity của view (A4.2); `$x` tạo `Binding`; sheet và alert điều khiển bằng state.
**Bài tập:** thêm `Toggle("Pin to top")` vào `CategoryFormView` (chỉ ở UI).

### A4.4 `@Observable` view model (2 ngày)

| Đọc theo thứ tự | Học gì |
|---|---|
| `FinanceFeatures/RecurringFormModel.swift` + `Features/Recurring/RecurringFormView.swift` | Mẫu chuẩn: `@MainActor @Observable final class`; view giữ model trong `@State`, tạo trong `.onAppear`, truyền cho view con có `@Bindable` |
| `Tests/FinanceFeaturesTests/RecurringFormModelTests.swift` | Test model không cần UI |
| `FinanceFeatures/SavingsGoalFormModel.swift` | Setter có logic, `@ObservationIgnored` |
| `FinanceFeatures/TransactionFormModel.swift` | `Mode` enum có associated value |
| `TransactionListModel` + `TransactionListView` + `TransactionFilterView` | Một model, hai view |
| `FinanceFeatures/OverviewModels.swift` + `ReportsView` | `LoadState` (tương đương `AsyncValue`) |

**Cần nắm:** theo dõi theo từng thuộc tính được đọc; `@State` sở hữu, `@Bindable` để tạo binding, `@Environment` để chia sẻ; không tạo model trong `body`.
**Bài tập (quan trọng nhất phần A):** `CategoryFormModel` nay đã có sẵn (lời giải mẫu). Tạo một nhánh, xoá `CategoryFormModel.swift`, tự viết lại từ `CategoryFormView` mà không nhìn bản cũ, rồi chạy `CategoryFormModelTests` (5 test) để kiểm tra. So sánh với bản gốc bằng `git diff`.

### A4.5 `@Environment` và DI (nửa ngày)

`App/PersonalFinanceApp.swift` (`LaunchState`), `App/AppContainer.swift`, `Support/PreviewSupport.swift`, các giá trị có sẵn `\.dismiss`, `\.scenePhase`, `\.openURL`. Thiếu environment thì app crash lúc chạy.

### A4.6 SwiftData + `@Query` (2–3 ngày)

| Đọc theo thứ tự | Học gì |
|---|---|
| `Schema/SchemaV1+Models.swift` | `@Model`, `@Relationship(deleteRule:)`, `#Index` |
| `Features/Wallets/WalletListView.swift` | `@Query(filter:sort:)` tự cập nhật |
| `Features/Wallets/WalletDetailView.swift` | Object `@Model` qua navigation, kiểm tra `isDeleted` |
| `Services/WalletService.swift` | Ghi qua service, `saveOrRollback()` |
| `AppContainer.dataVersion` + `.task(id:)` ở `HomeView` | Làm mới số tổng hợp |
| `SchemaV2/V3.swift`, `FinanceMigrationPlan.swift` | Migration |

**Bài tập:** mục "Ví có số dư âm" trong `WalletListView`, kèm một test service. Phần sâu hơn (CoreData, threading) nằm ở B2.

### A4.7 Nghiệp vụ nhiều bước và state machine (1–2 ngày)

`TransactionService` (chuyển khoản, `insertCashFlow`/`insertTransfer`), `RecurringService.record`, `RestoreFlowModel`, `ImportFlowModel`, `BackupService`/`ImportService` (kiểm tra hết rồi mới ghi; hoặc thành công hết, hoặc không đổi gì).

### Tóm tắt lộ trình state

```
Rendering & identity     (A4.2) quyết định khi nào state sống hay bị reset
        ▼
@State / @Binding        CategoryFormView, AmountField, PeriodPicker, CategoryPickerView
        ▼  form phức tạp, cần test, nhiều view dùng chung
@Observable + @Bindable  RecurringFormModel → TransactionFormModel → TransactionListModel
        ▼  dependency dùng chung toàn app
@Environment             AppContainer, \.dismiss, \.scenePhase
        ▼  dữ liệu cần lưu lại
SwiftData + @Query       WalletListView + WalletService + dataVersion
        ▼  thao tác nhiều bước, có thể thất bại
Service / state machine  TransactionService, RecurringService.record, Restore/ImportFlowModel
```

## A5. Điều hướng (1 ngày)

| Level | File | Học gì |
|---|---|---|
| 1. Trực tiếp | `CategoryFormView` (sheet), `TransactionFormView` (link sang `CategoryPickerView`) | `.sheet`, `NavigationLink { }`, `dismiss()` |
| 2. Path | `Support/NavigationDestinations.swift`, `WalletListView` | `NavigationLink(value:)`, `NavigationStack(path:)` |
| 3. Tab | `App/RootView.swift`, `FinanceFeatures/AppRouter.swift` | Mỗi tab một `NavigationPath` |
| 4. Từ bên ngoài | `App/NotificationResponder.swift` | Chạm thông báo mở màn hình Due |

**Bài tập:** thêm `AppScreen.about` vào tab More.

## A6. Danh sách, form, tương tác và animation (1 ngày)

| Kỹ thuật | Nơi xem |
|---|---|
| `List`, `Section`, `ForEach` | `WalletListView`, `BudgetListView` |
| `swipeActions`, `contextMenu` | `DueOccurrencesView` |
| `.searchable` | `TransactionListView` |
| `Form`, `Picker`, `DatePicker`, `Stepper` | `RecurringFormView` |
| `confirmationDialog` | `RecurringDetailView` |
| Lỗi thống nhất | `Support/ErrorAlert.swift` |
| `fileImporter` / `fileExporter` | `Features/Backup/BackupView.swift` |
| `@FocusState` | `ContributionFormView` (`SavingsGoalFormView.swift`) |

**Animation** (code gần như chưa có, nên học qua lab):
- `withAnimation { state = … }` tương đương implicit animation khi gọi `setState`; `.animation(.default, value: x)` gắn với một giá trị cụ thể.
- `.transition(.move(edge:))` khi view được thêm hoặc bỏ (cần identity, xem A4.2); `.contentTransition(.numericText())` cho số; `matchedGeometryEffect` giống `Hero`.

**Lab A6:** số tài sản ròng trên Home chạy số khi thay đổi (`contentTransition(.numericText())`); thẻ "Due" trượt vào hoặc ra khi danh sách đổi (`transition`); tôn trọng cài đặt `accessibilityReduceMotion`.

## A7. Biểu đồ, trợ năng, bản địa hoá (1 ngày)

- `DesignSystem/Charts/ChartComponents.swift`: Swift Charts, bảng số liệu đi kèm.
- `MoneyText`: `accessibilityLabel`; thử Dynamic Type lớn nhất và VoiceOver.
- Bản địa hoá: `Text("…")` nhận `LocalizedStringKey`; `String(localized:)`; định dạng bằng `FormatStyle` (`MoneyFormatter`). **Lab:** làm M7 trong `docs/ROADMAP.md` (String Catalog, `vi`).

## A8. Concurrency (1 ngày)

| File | Học gì |
|---|---|
| `App/ReminderCoordinator.swift` | `async/await`, `@MainActor` |
| `App/NotificationResponder.swift` | Delegate `nonisolated`, `await MainActor.run`, `@unchecked Sendable` |
| `HomeView` (`.task(id:)`) | Task gắn với vòng đời view, tự huỷ |

**Cần nắm:** `Task`, huỷ task, `actor`, `Sendable`, vì sao model SwiftData không được truyền qua actor khác (xem B2).

## A9. Lần theo một tính năng từ đầu đến cuối: "Thêm một khoản chi"

1. `HomeView`: nút "Add Transaction" bật `@State showingNewTransaction` và mở `.sheet` với `TransactionFormView`.
2. `TransactionFormView`: `.onAppear` tạo `TransactionFormModel` từ `app.transactions`.
3. Các field bind vào model; `model.canSave` bật/tắt nút Save.
4. `model.save()` tạo `CashFlowDraft` rồi gọi `TransactionService.create`.
5. `LedgerRules.validateCashFlow`, chèn `LedgerTransaction` + `LedgerEntry`, rồi `saveOrRollback()`.
6. `ModelContext.didSave` làm tăng `AppContainer.dataVersion`.
7. `HomeView` gọi `DashboardModel.reload()`; `WalletListView` tự cập nhật nhờ `@Query`.
8. `RootView` cập nhật nhắc nhở và cảnh báo ngân sách.

Đặt breakpoint ở từng bước để xem thứ tự thực sự.

---

# Phần B — Nền tảng native

## B1. UIKit & iOS Lifecycle Fundamentals (1–2 tuần)

**Vì sao cần:** phần lớn codebase iOS ngoài thị trường vẫn là UIKit hoặc trộn UIKit với SwiftUI; SwiftUI còn thiếu một số thứ; phỏng vấn Senior hầu như luôn hỏi. App này chỉ dùng SwiftUI, nên phần này **học qua lab**.

**Vòng đời app**

| Tầng | API | Trong code |
|---|---|---|
| Process | `UIApplicationDelegate`: launch, push token, background `URLSession` | (chưa có) — `NotificationResponder` đang được gắn trong `PersonalFinanceApp.init` |
| Scene / cửa sổ | `UISceneDelegate` ↔ SwiftUI `Scene`, `scenePhase` (`active`/`inactive`/`background`) | `RootView` và `HomeView` (`RefreshKey`) làm mới khi `scenePhase` đổi |
| View controller | `viewDidLoad`, `viewWillAppear`, `viewDidDisappear` ↔ `.onAppear`, `.task`, `.onDisappear` | — |

**Khái niệm UIKit cốt lõi:** cây `UIView`/`UIViewController`, `UINavigationController`, Auto Layout (constraint, intrinsic content size, hugging/compression ↔ `layoutPriority`), `UICollectionView` với diffable data source và tái sử dụng cell, pattern delegate/data source, target-action, responder chain.

**Cầu nối UIKit ↔ SwiftUI:** `UIViewRepresentable` / `UIViewControllerRepresentable` (`makeUIView`, `updateUIView`, `Coordinator` cho delegate), `UIHostingController` (SwiftUI nằm trong UIKit), `UIHostingConfiguration` (cell SwiftUI trong `UICollectionView`).

**Bàn phím:** `@FocusState`, `ToolbarItemGroup(placement: .keyboard)`, `.submitLabel`, `.scrollDismissesKeyboard(.interactively)`; bên UIKit là notification bàn phím và `keyboardLayoutGuide`.

**Safe area:** `.safeAreaInset(edge:)`, `.ignoresSafeArea`, `safeAreaLayoutGuide`.

**Chạy nền:** app bị tạm dừng gần như ngay khi vào nền. Những gì iOS cho phép: `BGAppRefreshTask`/`BGProcessingTask`, background `URLSession`, silent push, local notification đã lên lịch. Đây là lý do app ghi giới hạn "không chạy nền" (`NotificationSettingsView`).

**Labs B1**
1. **AppDelegate và log vòng đời:** thêm `@UIApplicationDelegateAdaptor`, chuyển việc gắn `NotificationResponder` vào `didFinishLaunching`, ghi log bằng `Logger` ở mọi sự kiện vòng đời và `scenePhase`. Quan sát thứ tự khi: mở app bình thường, mở bằng cách chạm thông báo lúc app đã bị tắt, vào nền rồi quay lại.
2. **Màn hình UIKit:** viết `WalletListViewController` bằng `UICollectionView` (list layout + `UICollectionViewDiffableDataSource`), cập nhật khi `ModelContext.didSave`, rồi nhúng vào app bằng `UIViewControllerRepresentable` sau một cờ debug. So sánh lượng code và cách cập nhật với `WalletListView`.
3. **`UIViewRepresentable` có Coordinator:** viết `AmountField` bằng `UITextField`, thêm `inputAccessoryView` với các nút nhanh (+10.000, +50.000). Dùng `Coordinator` làm delegate và tránh vòng lặp cập nhật giữa `updateUIView` và binding.
4. **Bàn phím và safe area:** form giao dịch có nút "Xong" trên bàn phím, Return chuyển sang field tiếp theo; nút "Add Transaction" ở Home dính đáy bằng `.safeAreaInset(edge: .bottom)`.
5. **Background refresh:** dùng `.backgroundTask(.appRefresh("…"))` để lên lịch lại nhắc nhở mỗi ngày. Cần bật Background Modes và khai báo `BGTaskSchedulerPermittedIdentifiers` trong Xcode; test bằng lệnh LLDB `_simulateLaunchForTaskWithIdentifier`.

## B2. Persistence sâu: SwiftData ↔ CoreData (1 tuần)

SwiftData chạy trên nền CoreData. Nhiều codebase hiện nay vẫn dùng CoreData trực tiếp.

| SwiftData (repo này) | CoreData |
|---|---|
| `ModelContainer` (`ModelContainerFactory`) | `NSPersistentContainer` |
| `ModelContext` | `NSManagedObjectContext` |
| `@Model` (`SchemaV1+Models.swift`) | Subclass `NSManagedObject` + file `.xcdatamodeld` |
| `FetchDescriptor` + `#Predicate` | `NSFetchRequest` + `NSPredicate` |
| `@Query` | `@FetchRequest` / `NSFetchedResultsController` |
| `VersionedSchema` + `FinanceMigrationPlan` | Model version + mapping model |
| `@ModelActor`, `PersistentIdentifier` | `newBackgroundContext()` + `perform`, `NSManagedObjectID` |

**Cần nắm:**
- Faulting (đối tượng được tải lười).
- **Quy tắc thread:** object chỉ dùng trên context tạo ra nó; truyền *id* chứ không truyền object qua actor khác.
- Merge policy, batch insert/delete.
- File WAL (`-wal`, `-shm`): copy riêng file `.store` là sai.
- Rollback (`saveOrRollback`).

Các cách lưu trữ khác: `UserDefaults` (`@AppStorage`), Keychain (bí mật), `FileManager` và data protection (`BackupFiles` dùng `.completeFileProtection`), CloudKit (không dùng, lý do ghi trong `ARCHITECTURE.md`).

**Labs B2**
1. **Xem SQL:** chạy app với launch argument `-com.apple.CoreData.SQLDebug 1`, mở Home và đếm số câu SQL. Tìm chỗ bị N+1 (số dư ví được tính bằng cách duyệt các dòng giao dịch).
2. **CoreData song song:** trong một project nháp dùng template CoreData, làm danh sách ví bằng `NSFetchedResultsController` và một tác vụ import chạy nền trên `newBackgroundContext()`. So sánh với `ImportService`.
3. **`@ModelActor`:** chuyển `ReportService.snapshot()` sang một `@ModelActor` (rủi ro hiệu năng đã ghi trong `ROADMAP.md`), chỉ trả về giá trị `Sendable`, và đo lại bằng B4.

## B3. Networking & Async Data Flow (1–2 tuần)

App chạy offline, nên phần này học qua tính năng **tỷ giá** (M10 trong `ROADMAP.md`).

**Cần nắm:**
- `URLSession`: `let (data, response) = try await session.data(for: request)`, kiểm tra `HTTPURLResponse.statusCode`, decode bằng `Codable` (xem cách `BackupCodec` cấu hình decoder).
- **Kiến trúc:** `protocol HTTPClient` inject qua `AppContainer`; tách DTO (dạng JSON) khỏi domain model (giống cặp `BackupDocument` ↔ `@Model`); đặt trong một module mới, ví dụ `FinanceNetworking`.
- **Lỗi:** error có kiểu cụ thể, timeout, retry có backoff (chỉ cho request idempotent), huỷ request (`.task` tự huỷ; kiểm tra `Task.isCancelled`), phát hiện mất mạng bằng `NWPathMonitor`.
- **Dữ liệu:** `URLCache` và ETag, phân trang bằng `AsyncSequence`, `AsyncStream` cho dữ liệu cập nhật liên tục, background `URLSession` để tải file lớn.
- **Offline-first:** database local là nguồn dữ liệu chính, mạng chỉ làm mới; cần chiến lược xử lý xung đột.
- **Bảo mật:** ATS (bắt buộc HTTPS), token lưu trong Keychain, certificate pinning (biết khi nào nên dùng), không log thông tin bí mật.
- **Test:** stub mạng bằng `URLProtocol`, inject `URLSession`.
- **Combine** (đọc hiểu code cũ): `Publisher`, `sink`, `AnyCancellable`, `ObservableObject` + `@Published` là cách viết trước iOS 17 tương đương `@Observable`.

**Labs B3**
1. **Tỷ giá:** `ExchangeRateService` lấy dữ liệu từ một API tỷ giá có hỗ trợ VND (hoặc một server giả lập chạy local). Lưu cache kèm thời điểm cập nhật, hiện "Tỷ giá lúc …", xử lý khi offline hoặc dữ liệu cũ. Test bằng `URLProtocol` cho các trường hợp: 200, 500, timeout, JSON sai, bị huỷ.
2. **Closure → AsyncSequence:** thay observer dạng closure `ModelContext.didSave` trong `AppContainer` bằng `for await _ in NotificationCenter.default.notifications(named:)` trong một `Task`. Học được cả AsyncSequence lẫn việc bỏ `[weak self]` một cách an toàn (nối sang B4).

## B4. Memory, Performance & Debugging (1–2 tuần, học bằng công cụ)

**ARC (Automatic Reference Counting):** Swift **không có GC dọn vòng tham chiếu** như Dart. `strong`/`weak`/`unowned`; vòng tham chiếu qua closure; delegate phải `weak`; observer của `NotificationCenter` giữ closure; `Task` giữ `self` cho tới khi chạy xong; `struct` thì không tạo vòng.

**Ví dụ thật trong code:**
- `AppContainer`: observer `didSave` dùng `[weak self]`. Observer token không bao giờ được gỡ; vô hại vì container sống suốt app, nhưng đây là một điểm đáng review.
- `NotificationResponder`: `UNUserNotificationCenter.delegate` là **weak**, nên `PersonalFinanceApp` phải giữ `let notificationResponder`. Nếu bỏ biến đó, delegate bị giải phóng và mọi lần chạm thông báo sẽ bị mất mà không báo lỗi.

**Công cụ:** Debug gauges, **Memory Graph Debugger**, Instruments (Time Profiler, Allocations, Leaks, Hangs, SwiftUI), `os.Logger` + `OSSignposter`, LLDB (`po`, `p`, `expression`, breakpoint có action, symbolic breakpoint), Thread Sanitizer, Main Thread Checker, MetricKit (số liệu từ máy người dùng).

**Labs B4**
1. **Leak có chủ đích:** thêm `var onChange: (() -> Void)?` vào `RecurringFormModel` và gán `model.onChange = { model.recalculate() }`. Mở/đóng form 5 lần, mở Memory Graph và thấy 5 instance còn sống. Sửa bằng `[weak model]`, kiểm tra lại bằng `deinit` có log.
2. **20.000 giao dịch:** thêm launch argument DEBUG `-SeedLargeLedger` để tạo dữ liệu lớn. Dùng Time Profiler và Hangs khi lưu một giao dịch để tìm `ReportService.snapshot` / `DashboardModel.reload` chạy trên main thread. Đặt `OSSignposter` quanh `reload`, đo trước và sau khi áp dụng lab B2-3.
3. **Số lần vẽ lại:** dùng SwiftUI instrument và `_printChanges` đếm số lần `body` chạy trên Home sau mỗi lần save. Tách view để chỉ thẻ đọc giá trị thay đổi mới vẽ lại.
4. **Allocations:** xuất CSV 20.000 dòng (`CSVTable.render` ghép chuỗi trong bộ nhớ) và đo đỉnh bộ nhớ. Cải thiện bằng cách ghi thẳng ra file theo từng phần.
5. **Concurrency:** bật Thread Sanitizer, chạy test, và giải thích vì sao Swift 6 đã chặn được phần lớn data race ngay lúc biên dịch.

## B5. Testing mở rộng (1 tuần)

**Đã có trong repo, đọc trước:**

| Loại | Ví dụ |
|---|---|
| Unit (Domain) | `MoneyTests`, `RecurrenceAndSavingsTests`, `BackupAndCSVTests`, `CSVImportParserTests` |
| Model (Features) | `TransactionFormModelTests`, `AppRouterTests`, `RestoreFlowModelTests`, `ImportFlowModelTests` |
| Integration với SwiftData in-memory | `LedgerServiceTests`, `BackupServiceTests`, `ImportServiceTests` |
| Migration | `MigrationTests.swift`: ghi file database V1/V3 thật bằng Core Data (model của phiên bản cũ), rồi mở bằng schema hiện tại |
| Lỗi và khôi phục | `invalidBackupChangesNothing`, `failedCommitKeepsNothing`, `noRestoreWhenSafetyCopyFails`, các test rollback |

**Chưa có, tự làm:**

| Loại | Lab |
|---|---|
| **UI test (XCUITest)** | Thêm target UI Testing trong Xcode, khởi chạy với `-UseInMemoryStore` (đã có sẵn trong `LaunchState`). Kịch bản: tạo ví → thêm khoản chi → số dư đúng. Dùng `accessibilityIdentifier`, page object, `waitForExistence`; xử lý hộp thoại xin quyền thông báo bằng `addUIInterruptionMonitor`. |
| **Database hỏng** | Ghi rác vào file database rồi khẳng định `makeContainer` ném `storeUnavailable` và **file vẫn còn nguyên**; UI test kiểm tra màn hình `StoreErrorView` hiện ra. |
| **Migration mới** | Khi làm M8: test V3 → V4 giữ nguyên số dư, và backup v1 vẫn khôi phục được. |
| **Performance** | XCTest `measure` với `XCTClockMetric` cho `ReportRules` trên 20.000 dòng (Swift Testing chưa có `measure`). |
| **Parameterized** | Chuyển các case trong `AmountInputParserTests` sang `@Test(arguments:)`; dùng `.tags`, `.timeLimit`, `confirmation` cho sự kiện async. |
| **Test plan, coverage, CI** | Test plan có cấu hình tiếng Việt và cấu hình bật Thread Sanitizer; bật code coverage; CI chạy `swift test` và `xcodebuild test -scheme PersonalFinance -destination 'platform=iOS Simulator,name=…'`. |
| Snapshot (tuỳ chọn) | Thư viện snapshot test cho `MoneyText` và các thẻ Dashboard ở chế độ sáng/tối và cỡ chữ lớn. |

---

# Phần C — Lên Senior

## C1. Kiến trúc ở quy mô lớn

- Đọc `docs/ARCHITECTURE.md` như một tập **quyết định thiết kế** (persistence boundary, consistency rule, navigation, restore một lần save): mỗi quyết định có lý do và có đánh đổi.
- So sánh MV / MVVM / TCA / VIPER: khi nào dùng cái nào; vì sao repo này chọn "view model chỉ ở nơi cần".
- Chia module theo tầng hoặc theo feature, DI qua composition root, ranh giới bằng protocol (và khi nào **không** cần, ví dụ không có lớp repository).
- **Lab:** viết ADR (Architecture Decision Record) cho mục #8 "khoản chi không thường xuyên" trong `ROADMAP.md`, rồi implement theo ADR đó.

## C2. Bảo mật và tích hợp hệ thống (gắn với M9)

Keychain, `LocalAuthentication` (Face ID), data protection, privacy manifest (`Resources/PrivacyInfo.xcprivacy`), App Intents/Shortcuts, WidgetKit + App Group (thiết kế snapshot JSON trong `ROADMAP.md`), universal link, push notification (APNs) so với local notification, audit trợ năng.
**Lab:** làm M9 theo `ROADMAP.md`.

## C3. Xcode, build và phát hành

- Cấu trúc project (thư mục đồng bộ), **conflict `project.pbxproj`**. Repo này đã gặp thật: Xcode đang mở đã ghi đè file project khi file bị sửa từ bên ngoài.
- Scheme, cấu hình Debug/Release, `xcconfig`, build setting `INFOPLIST_KEY_*`, signing (team, provisioning, capability), SPM.
- Đánh số version/build, Archive, TestFlight, App Store Connect, App Review (lưu ý riêng cho app tài chính), privacy nutrition label, crash và metric (Xcode Organizer, MetricKit).
- **Lab:** tách cấu hình bằng `xcconfig`, Archive bản Release, đưa lên TestFlight (cần tài khoản trả phí).

---

## Lộ trình gợi ý

| Tuần | Nội dung | Kết quả |
|---|---|---|
| 1 | A1–A3 | Đọc được Swift; lab `@Clamped` |
| 2 | A4.1–A4.3 | Các lab identity/layout; form chỉ dùng `@State` |
| 3 | A4.4–A4.5 | Tự viết lại `CategoryFormModel`, 5 test xanh |
| 4 | A4.6–A4.7, A5 | Tính năng nhỏ có service và test |
| 5 | A6–A9 | Animation, M7 (bản địa hoá), lần theo một tính năng |
| 6–7 | B1 | Lab AppDelegate, màn hình UIKit, Representable, background refresh |
| 8 | B2 | Đọc SQL, lab CoreData, `@ModelActor` |
| 9–10 | B3 | Lab tỷ giá có test mạng |
| 11–12 | B4 | Lab leak, 20.000 giao dịch, signpost |
| 13 | B5 | UI test, test database hỏng, CI |
| Sau đó | C1–C3 | ADR + M8, M9, phát hành TestFlight |

## Checklist

**Phần A**
- [ ] Giải thích được identity theo cấu trúc và tường minh, và khi nào `@State` bị reset
- [ ] Giải thích layout proposal → size → placement và vì sao `GeometryReader` dễ làm vỡ layout
- [ ] Chọn đúng giữa `@State`, `@Binding`, `@Observable` + `@Bindable`, `@Environment`
- [ ] Viết `@Observable` model có unit test
- [ ] Dùng `@Query` để đọc, service để ghi; hiểu "một thao tác = một save"
- [ ] Đọc hiểu `some`/`any`, result builder, property wrapper, macro

**Phần B**
- [ ] Mô tả vòng đời app/scene và những gì iOS cho chạy nền
- [ ] Viết được màn hình UIKit với diffable data source và nhúng qua Representable
- [ ] Giải thích quy tắc thread của CoreData/SwiftData và dùng `@ModelActor`
- [ ] Viết networking layer có lỗi rõ ràng, huỷ được, có cache và test bằng `URLProtocol`
- [ ] Tìm và sửa leak bằng Memory Graph; đo bằng Time Profiler và signpost
- [ ] Viết UI test, migration test, test lỗi và khôi phục; chạy test trên CI

**Phần C**
- [ ] Viết ADR và bảo vệ được lựa chọn kiến trúc
- [ ] Thêm Face ID, App Intents, widget một cách an toàn
- [ ] Archive và phát hành qua TestFlight

## Tài liệu nên đọc kèm

- **Apple:** SwiftUI Tutorials; tài liệu Observation, SwiftData, Core Data, URLSession; *The Swift Programming Language* (chương Concurrency, Memory Safety, ARC).
- **WWDC:** Demystify SwiftUI (2021) · Demystify SwiftUI performance (2023) · Compose custom layouts with SwiftUI (2022) · Explore SwiftUI animation (2023) · Discover Observation in SwiftUI (2023) · Meet SwiftData (2023) · Use SwiftUI with UIKit (2022) · Meet async/await in Swift (2021) · Migrate your app to Swift 6 (2024) · Detect and diagnose memory issues (2021) · Analyze hangs with Instruments (2023) · Meet Swift Testing (2024).
- **Sách:** *Thinking in SwiftUI*, *Advanced Swift* (objc.io); *100 Days of SwiftUI* (Hacking with Swift) để luyện thêm.
