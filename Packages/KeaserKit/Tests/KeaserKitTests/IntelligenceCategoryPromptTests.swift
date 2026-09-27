import Foundation
import Testing
@testable import KeaserKit

struct IntelligenceCategoryPromptTests {
    private let categories = ExpenseCategory.defaults()

    @Test func promptListsTheCategoriesWithHintsThenTheTitle() throws {
        let prompt = try #require(CategoryPrompt(categories: categories))
        #expect(prompt.choices == [
            "Food & Drinks", "Shopping", "Travel", "Services", "Entertainment", "Health", "Transportation", "none of these",
        ])
        #expect(prompt.prompt(for: "  Watsons \n") == """
        Categories:
        - Food & Drinks (restaurants, cafes, fast food, groceries, snacks, drinks, food delivery)
        - Shopping (shops, clothes, shoes, electronics, household goods, gifts, online orders)
        - Travel (flights, hotels, trips, holidays, sightseeing abroad)
        - Services (bills, utilities, phone and internet, repairs, cleaning, laundry, haircuts, fees)
        - Entertainment (streaming, movies, music, games, events, museums, hobbies, going out)
        - Health (doctors, dentists, pharmacies, medicine, gyms and fitness)
        - Transportation (taxis, ride hailing, public transport, fuel and petrol stations, parking, tolls, car costs)
        Expense title: "Watsons"
        """)
    }

    @Test func theInstructionsNameTheNoMatchChoice() {
        #expect(CategoryPrompt.instructions.contains("Choose \"none of these\" when no category clearly fits."))
        #expect(!CategoryPrompt.instructions.contains("\n"))
    }

    @Test func thePrefixIsEverythingButTheTitle() throws {
        let prompt = try #require(CategoryPrompt(categories: categories))
        #expect(prompt.prompt(for: "Zara")?.hasPrefix(prompt.promptPrefix) == true)
    }

    @Test func nothingToAskWithoutCategoriesOrTitle() throws {
        #expect(CategoryPrompt(categories: []) == nil)
        #expect(CategoryPrompt(categories: [ExpenseCategory(name: "  ", symbol: "tag")]) == nil)
        #expect(try #require(CategoryPrompt(categories: categories)).prompt(for: "   ") == nil)
    }

    @Test func choicesAreDistinctAndNeverTheNoMatchText() throws {
        let mine = ["Kids", " kids ", "", "None of these", "Café"].map { ExpenseCategory(name: $0, symbol: "tag") }
        let prompt = try #require(CategoryPrompt(categories: mine))
        #expect(prompt.choices == ["Kids", "Café", "none of these"])
        #expect(prompt.promptPrefix == "Categories:\n- Kids\n- Café\n")
    }

    @Test func aCategoryThePersonMadeGetsNoHint() {
        #expect(CategoryPrompt.hint(forCategoryNamed: "Kids") == nil)
        #expect(CategoryPrompt.hint(forCategoryNamed: " HEALTH ") == CategoryPrompt.hint(forCategoryNamed: "Health"))
        #expect(CategoryPrompt.hint(forCategoryNamed: "Health") != nil)
    }

    @Test func titlesAndNamesAreOneShortLineWithoutQuotes() throws {
        let prompt = try #require(CategoryPrompt(categories: categories))
        #expect(prompt.prompt(for: "Say \"hi\"\nnow")?.hasSuffix("Expense title: \"Say hi now\"") == true)
        let long = String(repeating: "a", count: 100)
        #expect(prompt.prompt(for: long)?.hasSuffix("\"" + String(repeating: "a", count: 60) + "\"") == true)

        let quoted = try #require(CategoryPrompt(categories: [ExpenseCategory(name: "Kids \"stuff\"\n", symbol: "tag")]))
        #expect(quoted.choices == ["Kids stuff", "none of these"])
    }

    @Test func answersMapBackToThisAccount() {
        let mine = ["Kids", "Café", "kids", "Kids \"stuff\""].map { ExpenseCategory(name: $0, symbol: "tag") }
        #expect(CategoryPrompt.category(named: "Kids", in: mine) == mine[0].id)
        #expect(CategoryPrompt.category(named: "cafe", in: mine) == mine[1].id)
        #expect(CategoryPrompt.category(named: "Kids stuff", in: mine) == mine[3].id)
        #expect(CategoryPrompt.category(named: "none of these", in: mine) == nil)
        #expect(CategoryPrompt.category(named: "Pets", in: mine) == nil)
        #expect(CategoryPrompt.category(named: nil, in: mine) == nil)
    }

    @Test func cacheKeyIgnoresCaseAndSpacesButNotTheCategories() throws {
        let prompt = try #require(CategoryPrompt(categories: categories))
        let other = try #require(CategoryPrompt(categories: [ExpenseCategory(name: "Kids", symbol: "tag")]))
        #expect(prompt.cacheKey(for: "Watsons") == prompt.cacheKey(for: " WATSONS"))
        #expect(prompt.cacheKey(for: "Watsons") != prompt.cacheKey(for: "Watson"))
        #expect(prompt.cacheKey(for: "Watsons") != other.cacheKey(for: "Watsons"))
    }
}
