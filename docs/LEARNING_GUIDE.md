# Học SwiftUI qua source code này (dành cho người từ Flutter)

Hướng dẫn đi theo thứ tự **từ đơn giản đến phức tạp**. Mỗi bài chỉ ra *đọc file nào*, *cần nắm gì*, *tương đương bên Flutter* và *một bài tập nhỏ* trên chính code này. Đọc kèm `docs/ARCHITECTURE.md` khi cần biết lý do thiết kế.

---

## 0. Bản đồ Flutter → SwiftUI

| Flutter | SwiftUI (trong repo này) | Khác biệt quan trọng |
|---|---|---|
| `Widget`, `build()` | `struct … : View`, `var body` | View là **struct giá trị**, bị tạo lại liên tục và rất rẻ. Không giữ state trong thuộc tính thường. |
| `StatefulWidget` + `setState` | `@State` | Không có `setState`: gán giá trị mới là UI tự vẽ lại. |
| Truyền callback `onChanged` / `TextEditingController` | `@Binding` (`$text`) | Binding là "con trỏ hai chiều" tới state của view cha. |
| `ChangeNotifier` / `ValueNotifier` / Riverpod `Notifier` | `@Observable class` | **Không có `notifyListeners()`.** SwiftUI tự theo dõi thuộc tính nào được *đọc* trong `body`, nên chỉ vẽ lại đúng chỗ cần. |
| `Provider` / `InheritedWidget` | `@Environment` | Ở đây chỉ có một dependency dùng chung là `AppContainer`. |
| `Consumer` / `context.watch` | Đọc thẳng `model.x` trong `body` | Có tracking tự động, không cần widget bọc. |
| `FutureBuilder` / `initState` gọi async | `.task { }` / `.task(id:)` | Tự huỷ khi view biến mất; `id` đổi thì chạy lại. |
| `StreamBuilder` trên database (Drift, Isar watch) | `@Query` (SwiftData) | Query tự cập nhật khi dữ liệu đổi. |
| sqflite / Drift / Isar | SwiftData `@Model` | Model là **class** (kiểu tham chiếu) và tự observable. |
| `Navigator 2.0` / GoRouter | `NavigationStack(path:)` + `navigationDestination(for:)` | Route là giá trị `Hashable`. |
| `showModalBottomSheet` / `showDialog` | `.sheet`, `.confirmationDialog`, `.alert` | Điều khiển bằng state (`isPresented`), không gọi hàm imperatively. |
| `ThemeData` | Token trong `DesignSystem/` + màu và font hệ thống | iOS ưu tiên control gốc của hệ thống thay vì tự vẽ. |
| `flutter_bloc` / state machine | `enum Step` trong `RestoreFlowModel`, `ImportFlowModel` | Enum có associated value thay cho class state. |
| Isolate | `actor`, `@MainActor`, `async/await`, `Sendable` | Swift 6 kiểm tra data race **ngay lúc biên dịch**. |
| `pubspec.yaml` / package | Swift Package (`Packages/FinanceKit/Package.swift`) | Module tách biệt, và compiler giữ ranh giới giữa chúng. |
| `flutter test`, widget test | `swift test`, Swift Testing (`@Test`, `#expect`) | Repo test model và service, không test view. |
| Hot reload | `#Preview` trong Xcode Canvas | Mỗi màn hình có preview với dữ liệu mẫu (`.sampleData`). |

**Ba khác biệt dễ vấp nhất:**
1. **Identity của view:** `@State` gắn với *vị trí* của view trong cây. Đổi `if/else` hoặc `.id(...)` là state bị reset, giống `Key` trong Flutter.
2. **Thứ tự modifier có ý nghĩa:** `.padding().background(.red)` khác `.background(.red).padding()`.
3. **Kiểu giá trị và kiểu tham chiếu:** `struct` (View, `Money`, draft) được copy khi gán, còn `class` (`@Observable` model, `@Model` SwiftData) được dùng chung.

---

## 1. Chuẩn bị (nửa ngày)

1. Mở `PersonalFinance.xcodeproj` và chạy app trên simulator.
2. Mở `Features/Home/HomeView.swift`, bật Canvas (⌥⌘↩) và xem hai preview *New user* và *With data*.
3. Chạy `cd Packages/FinanceKit && swift test` để thấy test chạy không cần simulator.
4. Lướt `README.md` (danh sách tính năng) và phần *Modules* trong `docs/ARCHITECTURE.md`.

**Cần nắm:** project gồm **app target** (giao diện) và **package FinanceKit** với 3 module:

```
FinanceDomain       Swift thuần: tiền, quy tắc, lịch          ← học Swift ở đây
FinancePersistence  SwiftData: model, schema, service           ← học dữ liệu ở đây
FinanceFeatures     @Observable view model, AppRouter           ← học state ở đây
PersonalFinance/    SwiftUI view                                ← học UI ở đây
```

---

## 2. Swift cơ bản qua FinanceDomain (1–2 ngày)

Đọc trước khi chạm vào SwiftUI. Đây là Swift thuần, không có UI.

| File | Học gì | Tương đương Dart |
|---|---|---|
| `FinanceDomain/Money.swift` | `struct`, `Equatable`, `Hashable`, hàm `throws`, `guard`, `Int64` thay vì `Double` cho tiền | class bất biến + `operator ==` |
| `FinanceDomain/AccountTypes.swift` | `enum` có `rawValue`, `CaseIterable`, computed property, `switch` phải đủ case | `enum` (Dart 3 enhanced enum) |
| `FinanceDomain/LedgerValidationError.swift` | Error là `enum`, `LocalizedError` | `sealed class` exception |
| `FinanceDomain/CurrencyDefinition.swift` | `static`, `extension`, optional (`?`, `if let`, `??`) | null safety |
| `FinanceDomain/RecurrenceRules.swift` | Hàm thuần, `Calendar`, `Date` | — |
| `Tests/FinanceDomainTests/MoneyTests.swift` | `@Test`, `#expect`, `#expect(throws:)` | `test()`, `expect()` |

**Cần nắm:** `let`/`var`, optional, `guard let`, `throws`/`try`, `struct` và `class`, `enum` có associated value, `extension`, `protocol`.

**Bài tập:** viết `Money.isGreater(than:)` và test cho nó trong `MoneyTests.swift`.

---

## 3. Hành trình state management

Phần chính. Học theo đúng thứ tự dưới đây, vì mỗi bước giải quyết một vấn đề mà bước trước chưa giải được.

### 3.1 View thuần, chưa có state: DesignSystem (nửa ngày)

| File | Học gì |
|---|---|
| `DesignSystem/Components/IconBadge.swift` | View nhỏ nhất: `struct`, `var body`, tham số `let` |
| `DesignSystem/Components/MoneyText.swift` | Tham số enum (`AmountTone`), computed property, **accessibility label** |
| `DesignSystem/Components/CardStyle.swift` | `ViewModifier` và `extension View { func cardStyle() }`, giống tự viết một "wrapper widget" |
| `DesignSystem/Metrics.swift`, `AppColor.swift` | Design token: `Spacing`, `Radius`, màu sáng/tối |

**Flutter:** đây là các `StatelessWidget`.
**Bài tập:** tạo component `TagChip(text:)` dùng `Spacing` và `Radius`, có `#Preview`.

### 3.2 `@State` và `@Binding`: state cục bộ (1 ngày)

| Đọc theo thứ tự | Vì sao chọn file này |
|---|---|
| `DesignSystem/Components/AmountField.swift` | `@Binding var text`: view con **không sở hữu** state. Preview dùng `@Previewable @State` để tạo state giả. |
| `DesignSystem/Components/PeriodPicker.swift` | Vừa có `@Binding var selection` (của cha) vừa có `@State` riêng (`showingCustom`, ngày tuỳ chỉnh): phân biệt state *của mình* và state *mượn của cha*. |
| `Features/Categories/CategoryFormView.swift` | Form hoàn chỉnh chỉ dùng `@State` (tên, loại, icon, màu), `$name` truyền xuống `TextField`, `didLoad` để nạp dữ liệu một lần, `@State error` điều khiển alert. |
| `Features/Transactions/CategoryPickerView.swift` | `@Binding selection` trả kết quả về form cha; `@State showingNewCategory` mở sheet. |
| `Features/More/NotificationSettingsView.swift` | `@AppStorage`: `@State` lưu vào UserDefaults, giống `shared_preferences`. |

**Cần nắm:**
- `@State` luôn là `private`, thuộc về đúng một view, và sống theo identity của view đó.
- `$x` tạo `Binding`. Truyền `Binding` xuống con thay cho cặp `value` + `onChanged` của Flutter.
- Sheet, alert, dialog đều bật/tắt bằng `@State` kiểu `Bool` hoặc `Item?`.
- Khi nào `@State` là đủ: form ít field, logic đơn giản (xem phần đánh giá trong `ARCHITECTURE.md`, bảng *Which forms have a model*).

**Bài tập:** thêm vào `CategoryFormView` một `Toggle("Pin to top")` bằng `@State`, chỉ ở UI và chưa lưu.

### 3.3 `@Observable` view model: logic tách khỏi view (2 ngày)

**Vấn đề cần giải:** form nhiều field ràng buộc nhau, cần unit test, hoặc nhiều view cùng dùng một state.

| Đọc theo thứ tự | Học gì |
|---|---|
| `FinanceFeatures/RecurringFormModel.swift` + `Features/Recurring/RecurringFormView.swift` | Mẫu chuẩn của repo: `@MainActor @Observable final class`, input là `var`, output là computed (`canSave`, `nextOccurrence`), `save() -> Bool`, `failure`. View giữ model bằng `@State private var model: …?`, tạo trong `.onAppear` (vì cần lấy service từ `@Environment`), rồi truyền vào view con có `@Bindable var model`. |
| `Tests/FinanceFeaturesTests/RecurringFormModelTests.swift` | Test model **không cần UI**: đây là lợi ích chính của việc tách. |
| `FinanceFeatures/SavingsGoalFormModel.swift` | Setter có logic (`currency` đổi thì bỏ ví không hợp lệ), `@ObservationIgnored` cho dependency. |
| `FinanceFeatures/TransactionFormModel.swift` + `TransactionFormView.swift` | Model lớn nhất: 3 chế độ (thu, chi, chuyển khoản), `Mode` enum có associated value (`.create(wallet:)`, `.edit(transaction)`). |
| `FinanceFeatures/TransactionListModel.swift` + `TransactionListView.swift` + `TransactionFilterView.swift` | **Một model, hai view**: list và sheet lọc cùng `@Bindable` vào một model; `.searchable(text: $model.query.searchText)`. |
| `FinanceFeatures/OverviewModels.swift` + `Features/Reports/ReportsView.swift` | `LoadState` (idle, loaded, failed) và `switch model.state` trong `body`: tương đương `AsyncValue` của Riverpod. |

**Cần nắm:**
- `@Observable` theo dõi theo **từng thuộc tính được đọc**: view chỉ vẽ lại khi thuộc tính nó đọc thay đổi.
- Bộ ba: `@State` *sở hữu* model, `@Bindable` để tạo `$model.x`, `@Environment` để *chia sẻ*.
- `@ObservationIgnored` cho những thứ không cần theo dõi (service, parser, clock).
- Truyền `now: () -> Date` vào model để test được thời gian, giống inject `Clock`.
- **Không** tạo model trong `body` (`let m = Model()`), vì mỗi lần vẽ lại sẽ tạo model mới.

**Bài tập:** tách `CategoryFormView` thành `CategoryFormModel` theo mẫu `RecurringFormModel`, kèm 3 test. Đây là bài tập tốt nhất của cả hướng dẫn.

### 3.4 `@Environment` và dependency injection (nửa ngày)

| File | Học gì |
|---|---|
| `App/PersonalFinanceApp.swift` | Điểm khởi đầu `@main`, `LaunchState` (database mở được hay lỗi), `.environment(container)` |
| `App/AppContainer.swift` | Composition root: mọi service và `router`, `dataVersion` |
| `Support/PreviewSupport.swift` | Preview dùng container in-memory: `.sampleData`, `.emptyStore` |
| Bất kỳ view nào | `@Environment(AppContainer.self) private var app`; giá trị có sẵn: `\.dismiss`, `\.scenePhase`, `\.openURL` |

**Flutter:** `ProviderScope` + `ref.read(serviceProvider)`. **Cần nắm:** environment truyền xuống *toàn bộ cây con*; thiếu environment thì app **crash** ở runtime, nên preview phải dùng trait.

### 3.5 SwiftData + `@Query`: dữ liệu bền vững (2–3 ngày)

| Đọc theo thứ tự | Học gì |
|---|---|
| `FinancePersistence/Schema/SchemaV1+Models.swift` | `@Model final class`, `@Relationship(deleteRule:)`, `#Index`; quy ước enum lưu dạng `String` |
| `Features/Wallets/WalletListView.swift` | `@Query(filter: #Predicate { $0.archivedAt == nil }, sort: \.sortOrder)`: danh sách **tự cập nhật** |
| `Features/Wallets/WalletDetailView.swift` | Nhận object `@Model` qua navigation; kiểm tra `isDeleted` khi bản ghi bị xoá ở nơi khác |
| `FinancePersistence/Services/WalletService.swift` | **Ghi luôn đi qua service**: validate → ghi → `saveOrRollback()` một lần |
| `FinancePersistence/ModelContainerFactory.swift` | Container, in-memory cho test, `saveOrRollback` |
| `App/AppContainer.swift` (`dataVersion`) + `Features/Home/HomeView.swift` (`.task(id:)`) | Làm mới các số tổng hợp sau mỗi lần save |
| `Schema/SchemaV2.swift`, `SchemaV3.swift`, `FinanceMigrationPlan.swift` | Versioned schema và migration |
| `Tests/FinancePersistenceTests/TestSupport.swift`, `LedgerServiceTests.swift` | Test với database in-memory |

**Cần nắm:**
- **Đọc** danh sách đơn giản thì dùng `@Query` trong view. **Ghi** luôn qua service, không sửa model trực tiếp trong view.
- Autosave tắt, nên mỗi thao tác là đúng một `save()`. Lỗi thì `rollback()` (xem phần *Consistency rule*).
- Số tổng hợp (dashboard, báo cáo) không dùng `@Query`; chúng được tính trên snapshot, chạy lại khi `dataVersion` đổi.
- `#Predicate` có hạn chế: enum và optional hay lỗi, vì vậy model lưu `typeRaw: String`.
- Đổi model đã phát hành thì **phải** thêm `SchemaVn` và một migration stage.

**Bài tập:** thêm vào `WalletListView` một mục "Ví có số dư âm" dùng `@Query` hoặc lọc trên kết quả query. Rồi viết một test service nhỏ trong `LedgerServiceTests`.

### 3.6 Nghiệp vụ nhiều bước và state machine (1–2 ngày)

| File | Học gì |
|---|---|
| `Services/TransactionService.swift` | Chuyển khoản = 1 giao dịch + 2 dòng, ghi cùng nhau; `insertCashFlow`/`insertTransfer` (chưa save) để ghép vào thao tác lớn hơn |
| `Services/RecurringService.swift` (`record`) | Ghi giao dịch và đánh dấu đã xử lý trong **một** lần save |
| `FinanceFeatures/RestoreFlowModel.swift` | State machine `idle → review → finished / failed` bằng `enum Step` |
| `Services/BackupService.swift`, `ImportService.swift` | Kiểm tra toàn bộ trước, ghi sau; hoặc thành công hết, hoặc không đổi gì |

**Flutter:** giống `Bloc` với các state `sealed`. **Cần nắm:** khi nào đặt logic ở Domain (hàm thuần), Service (cần database) hay Model (cần state UI).

### Tóm tắt lộ trình state

```
@State / @Binding        CategoryFormView, AmountField, PeriodPicker, CategoryPickerView
        │ form phức tạp, cần test, nhiều view dùng chung
        ▼
@Observable + @Bindable  RecurringFormModel → TransactionFormModel → TransactionListModel (+ FilterView)
        │ dependency dùng chung toàn app
        ▼
@Environment             AppContainer (service, router), \.dismiss, \.scenePhase
        │ dữ liệu cần lưu lại
        ▼
SwiftData + @Query       WalletListView (@Query) + WalletService (ghi) + dataVersion (làm mới)
        │ thao tác nhiều bước, có thể thất bại
        ▼
Service / state machine  TransactionService, RecurringService.record, RestoreFlowModel, ImportFlowModel
```

---

## 4. Điều hướng (1 ngày)

Đọc theo đúng các level trong `ARCHITECTURE.md` › *Navigation*.

| Level | File | Học gì |
|---|---|---|
| 1. Trực tiếp | `CategoryFormView` (sheet), `TransactionFormView` (link sang `CategoryPickerView`) | `.sheet(isPresented:)`, `NavigationLink { }`, `dismiss()` |
| 2. Path | `Support/NavigationDestinations.swift`, `Features/Wallets/WalletListView.swift` | `NavigationLink(value:)` + `navigationDestination(for:)`, `NavigationStack(path:)` |
| 3. Tab | `App/RootView.swift`, `FinanceFeatures/AppRouter.swift` | `TabView(selection:)`, mỗi tab một `NavigationPath` |
| 4. Từ bên ngoài | `App/NotificationResponder.swift`, `AppRouter.receive/resolvePending` | Chạm thông báo mở thẳng màn hình Due |

**Flutter:** GoRouter có `ShellRoute` cho tab. **Bài tập:** thêm `AppScreen.about` và một màn hình "About" vào tab More.

---

## 5. Danh sách, form, tương tác (rải rác khi đọc)

| Kỹ thuật | Nơi xem |
|---|---|
| `List`, `Section`, `ForEach` có `id` | `WalletListView`, `BudgetListView` |
| Vuốt để thao tác, menu nhấn giữ | `Features/Recurring/DueOccurrencesView.swift` (`swipeActions`, `contextMenu`) |
| Tìm kiếm | `TransactionListView` (`.searchable`) |
| `Form`, `Picker`, `DatePicker`, `Toggle`, `Stepper` | `RecurringFormView` |
| Xác nhận xoá | `RecurringDetailView` (`confirmationDialog`) |
| Hiển thị lỗi thống nhất | `Support/ErrorAlert.swift` (`.errorAlert($error)`) |
| Chọn và lưu file | `Features/Backup/BackupView.swift` (`fileImporter`, `fileExporter`) |

## 6. Biểu đồ và trợ năng (nửa ngày)

- `DesignSystem/Charts/ChartComponents.swift`: Swift Charts (`Chart`, `BarMark`, `LineMark`), trục rút gọn, bảng số liệu đi kèm.
- `MoneyText`: `accessibilityLabel` đọc "Expense 65.000 ₫" thay vì chỉ dựa vào màu.
- Thử Dynamic Type: Xcode › Environment Overrides › Text size lớn nhất.

## 7. Concurrency, async (1 ngày, sau khi đã vững các phần trên)

| File | Học gì |
|---|---|
| `App/ReminderCoordinator.swift` | `async/await` với `UNUserNotificationCenter`, `@MainActor` |
| `App/NotificationResponder.swift` | Delegate `nonisolated`, `await MainActor.run { }`, `@unchecked Sendable` |
| `HomeView` (`.task(id:)`) | Task gắn với vòng đời view |

**Flutter:** `async/await` giống nhau, nhưng Swift 6 bắt lỗi data race lúc **biên dịch**. Mọi thứ UI đều `@MainActor`, tương tự main isolate.

## 8. Lần theo một tính năng từ đầu đến cuối

Bài tổng hợp nên làm sau phần 3: **"Thêm một khoản chi"**.

1. `HomeView`: nút "Add Transaction" bật `@State showingNewTransaction`, mở `.sheet` với `TransactionFormView(mode: .create(wallet: nil))`.
2. `TransactionFormView`: `.onAppear` tạo `TransactionFormModel` từ `app.transactions` lấy qua `@Environment`.
3. Người dùng nhập liệu, các field bind thẳng vào model (`$model.amountText`); `model.canSave` bật/tắt nút Save.
4. `model.save()` tạo `CashFlowDraft` rồi gọi `TransactionService.create`.
5. `TransactionService`: `LedgerRules.validateCashFlow`, chèn `LedgerTransaction` + `LedgerEntry`, rồi `saveOrRollback()`.
6. `ModelContext.didSave` làm tăng `AppContainer.dataVersion`.
7. `HomeView` chạy lại `.task(id: RefreshKey(...))` và gọi `DashboardModel.reload()`; `WalletListView` tự cập nhật nhờ `@Query`.
8. `RootView` chạy lại `.task(id: app.dataVersion)` để cập nhật nhắc nhở và cảnh báo ngân sách.

Đặt breakpoint ở mỗi bước và chạy app để xem thứ tự thực sự.

## 9. Lộ trình gợi ý

| Tuần | Nội dung | Kết quả |
|---|---|---|
| 1 | Phần 1–2, 3.1–3.2 | Đọc được Swift; tự làm form chỉ dùng `@State` |
| 2 | 3.3–3.4 | Tách `CategoryFormModel` có test (bài tập 3.3) |
| 3 | 3.5–3.6 | Thêm một tính năng nhỏ có service và test |
| 4 | 4–8 | Lần theo một tính năng; làm một mục nhỏ trong `docs/ROADMAP.md` (ví dụ mốc cảnh báo riêng cho từng ngân sách) |

## 10. Checklist "đã nắm"

- [ ] Giải thích được vì sao View là `struct`, và khi nào `@State` bị reset
- [ ] Chọn đúng giữa `@State`, `@Binding`, `@Observable` + `@Bindable`, `@Environment`
- [ ] Viết được `@Observable` model có unit test, không phụ thuộc UI
- [ ] Dùng `@Query` để đọc, và biết vì sao không ghi trực tiếp trong view
- [ ] Hiểu `saveOrRollback()` và "một thao tác = một save"
- [ ] Thêm được một màn hình vào navigation bằng `NavigationLink(value:)`
- [ ] Viết test bằng Swift Testing cho Domain, Service và Model
- [ ] Đọc hiểu được `@MainActor`, `async`, `.task(id:)`

## Tài liệu chính thức nên đọc kèm

- Apple: *SwiftUI Tutorials* (Landmarks), *Managing model data in your app* (Observation), *SwiftData* documentation
- *The Swift Programming Language* (bản Swift 6): chương Concurrency
- WWDC23: "Discover Observation in SwiftUI", "Meet SwiftData"; WWDC24: "Migrate your app to Swift 6"
