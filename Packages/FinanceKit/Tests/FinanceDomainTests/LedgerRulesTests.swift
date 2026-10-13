import Foundation
import Testing
import FinanceDomain

@Suite("Ledger rules")
struct LedgerRulesTests {
    private func expense(
        _ minor: Int64 = 65_000,
        currency: CurrencyDefinition = .vnd,
        walletCurrency: CurrencyDefinition = .vnd,
        category: CategoryType? = .expense
    ) -> CashFlowCandidate {
        CashFlowCandidate(
            kind: .expense,
            amount: Money(minorUnits: minor, currency: currency),
            walletCurrency: walletCurrency,
            categoryType: category
        )
    }

    @Test func validExpenseAndIncomePass() throws {
        try LedgerRules.validateCashFlow(expense())
        var income = expense(category: .income)
        income.kind = .income
        try LedgerRules.validateCashFlow(income)
    }

    @Test(arguments: [Int64(0), -1])
    func amountMustBePositive(minor: Int64) {
        #expect(throws: LedgerValidationError.nonPositiveAmount) {
            try LedgerRules.validateCashFlow(expense(minor))
        }
    }

    @Test func currencyMustMatchWallet() {
        #expect(throws: LedgerValidationError.currencyMismatch(walletCurrency: "VND", amountCurrency: "USD")) {
            try LedgerRules.validateCashFlow(expense(500, currency: .usd))
        }
    }

    @Test func categoryIsRequiredAndMustMatchKind() {
        #expect(throws: LedgerValidationError.missingCategory) {
            try LedgerRules.validateCashFlow(expense(category: nil))
        }
        #expect(throws: LedgerValidationError.categoryTypeMismatch(required: .expense, actual: .income)) {
            try LedgerRules.validateCashFlow(expense(category: .income))
        }
    }

    @Test func archivedWalletIsReadOnly() {
        var candidate = expense()
        candidate.walletIsArchived = true
        #expect(throws: LedgerValidationError.archivedWallet) {
            try LedgerRules.validateCashFlow(candidate)
        }
    }

    @Test func archivedCategoryCanBeKeptButNotNewlyChosen() throws {
        var candidate = expense()
        candidate.categoryIsArchived = true
        #expect(throws: LedgerValidationError.archivedCategory) {
            try LedgerRules.validateCashFlow(candidate)
        }
        candidate.keepsExistingCategory = true
        try LedgerRules.validateCashFlow(candidate)
    }

    @Test func transfersAreRejectedByCashFlowRules() {
        var candidate = expense(category: nil)
        candidate.kind = .transfer
        #expect(throws: LedgerValidationError.transfersNotSupported) {
            try LedgerRules.validateCashFlow(candidate)
        }
    }

    @Test func signedAmounts() throws {
        let amount = Money(minorUnits: 65_000, currency: .vnd)
        #expect(try LedgerRules.signedMinorUnits(for: .income, amount: amount) == 65_000)
        #expect(try LedgerRules.signedMinorUnits(for: .expense, amount: amount) == -65_000)
    }

    @Test func balanceIsOpeningPlusEntries() throws {
        let opening = Money(minorUnits: 1_500_000, currency: .vnd)
        let entries = [-65_000, 25_000_000, -48_000].map { Money(minorUnits: Int64($0), currency: .vnd) }

        #expect(try LedgerRules.balance(opening: opening, entries: entries).minorUnits == 26_387_000)
        #expect(try LedgerRules.balance(opening: opening, entries: []) == opening)
    }

    @Test func balanceRejectsForeignEntries() {
        let opening = Money(minorUnits: 0, currency: .vnd)
        #expect(throws: FinancialError.currencyMismatch(expected: "VND", actual: "USD")) {
            try LedgerRules.balance(opening: opening, entries: [Money(minorUnits: 1, currency: .usd)])
        }
    }
}

@Suite("Wallet and text rules")
struct WalletRulesTests {
    @Test func liabilityOpeningBalanceIsStoredAsDebt() throws {
        let owed = Money(minorUnits: 2_000_000, currency: .vnd)

        let stored = try WalletRules.storedOpeningBalance(entered: owed, accountClass: .liability)
        #expect(stored.minorUnits == -2_000_000)
        #expect(try WalletRules.enteredOpeningBalance(stored: stored, accountClass: .liability) == owed)

        #expect(try WalletRules.storedOpeningBalance(entered: owed, accountClass: .asset) == owed)
    }

    @Test func enteredOpeningBalanceCannotBeNegative() {
        #expect(throws: LedgerValidationError.negativeAmount) {
            try WalletRules.storedOpeningBalance(entered: Money(minorUnits: -1, currency: .vnd), accountClass: .asset)
        }
    }

    @Test func namesAreTrimmedAndRequired() throws {
        #expect(try TextRules.normalizedName("  Cash  ") == "Cash")
        #expect(throws: LedgerValidationError.emptyName) { try TextRules.normalizedName("   ") }
        #expect(try TextRules.normalizedName(String(repeating: "a", count: 100)).count == TextRules.maximumNameLength)
    }

    @Test func optionalTextBecomesNilWhenBlank() {
        #expect(TextRules.optionalText("  ") == nil)
        #expect(TextRules.optionalText(nil) == nil)
        #expect(TextRules.optionalText(" Lunch ") == "Lunch")
    }
}
