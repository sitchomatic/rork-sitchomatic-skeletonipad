import Testing
import Foundation
@testable import Sitchomatic

/// Tests for PPSRCard model - credit card data parsing and validation
@Suite("PPSR Card Tests")
struct PPSRCardTests {

    // MARK: - Card Brand Detection

    @Test("Visa card detection")
    func testVisaDetection() {
        #expect(CardBrand.detect("4111111111111111") == .visa)
        #expect(CardBrand.detect("4") == .visa)
        #expect(CardBrand.detect("4222222222222222") == .visa)
    }

    @Test("Mastercard detection")
    func testMastercardDetection() {
        #expect(CardBrand.detect("5111111111111111") == .mastercard)
        #expect(CardBrand.detect("2221000000000000") == .mastercard)
        #expect(CardBrand.detect("5") == .mastercard)
    }

    @Test("American Express detection")
    func testAmexDetection() {
        #expect(CardBrand.detect("371111111111111") == .amex)
        #expect(CardBrand.detect("341111111111111") == .amex)
        #expect(CardBrand.detect("34") == .amex)
        #expect(CardBrand.detect("37") == .amex)
    }

    @Test("JCB detection")
    func testJCBDetection() {
        #expect(CardBrand.detect("3511111111111111") == .jcb)
        #expect(CardBrand.detect("35") == .jcb)
    }

    @Test("Discover detection")
    func testDiscoverDetection() {
        #expect(CardBrand.detect("6011111111111111") == .discover)
        #expect(CardBrand.detect("6511111111111111") == .discover)
        #expect(CardBrand.detect("6441111111111111") == .discover)
    }

    @Test("Diners Club detection")
    func testDinersDetection() {
        #expect(CardBrand.detect("36111111111111") == .dinersClub)
        #expect(CardBrand.detect("38111111111111") == .dinersClub)
        #expect(CardBrand.detect("300111111111") == .dinersClub)
    }

    @Test("UnionPay detection")
    func testUnionPayDetection() {
        #expect(CardBrand.detect("6211111111111111") == .unionPay)
        #expect(CardBrand.detect("62") == .unionPay)
    }

    @Test("Unknown brand for invalid cards")
    func testUnknownBrand() {
        #expect(CardBrand.detect("9111111111111111") == .unknown)
        #expect(CardBrand.detect("") == .unknown)
        #expect(CardBrand.detect("abc") == .unknown)
    }

    // MARK: - Card Number Validation

    @Test("Valid card number lengths")
    func testValidCardNumberLengths() {
        // Visa: 13, 16, 19 digits
        #expect(CardBrand.detect("4111111111111") == .visa) // 13
        #expect(CardBrand.detect("4111111111111111") == .visa) // 16

        // Amex: 15 digits
        #expect(CardBrand.detect("371449635398431") == .amex)
    }

    @Test("Card number with spaces and dashes")
    func testCardNumberFormatting() {
        #expect(CardBrand.detect("4111-1111-1111-1111") == .visa)
        #expect(CardBrand.detect("4111 1111 1111 1111") == .visa)
    }

    // MARK: - Regex Pattern Parsing

    @Test("Parse card from CCNUM format")
    func testCCNUMParsing() {
        let text = "CCNUM: 4111111111111111 CVV: 123 EXP: 12/25"
        let card = PPSRCard.parseRichTextBlock(text)
        #expect(card != nil)
        #expect(card?.number == "4111111111111111")
        #expect(card?.cvv == "123")
        #expect(card?.expiryMonth == "12")
        #expect(card?.expiryYear == "25")
    }

    @Test("Parse card from CC# format")
    func testCCHashParsing() {
        let text = "CC#5111111111111111 CVC:456 Expiry:11/26"
        let card = PPSRCard.parseRichTextBlock(text)
        #expect(card != nil)
        #expect(card?.number == "5111111111111111")
        #expect(card?.cvv == "456")
    }

    @Test("Parse card from Card Number format")
    func testCardNumberParsing() {
        let text = "Card Number: 371449635398431 CVV2: 9876 EXP DATE: 03/27"
        let card = PPSRCard.parseRichTextBlock(text)
        #expect(card != nil)
        #expect(card?.number == "371449635398431")
        #expect(card?.cvv == "9876")
        #expect(card?.expiryMonth == "03")
        #expect(card?.expiryYear == "27")
    }

    @Test("Invalid OCR text returns nil")
    func testInvalidOCRText() {
        #expect(PPSRCard.parseRichTextBlock("No card data here") == nil)
        #expect(PPSRCard.parseRichTextBlock("") == nil)
        #expect(PPSRCard.parseRichTextBlock("CCNUM: invalid") == nil)
    }

    @Test("Partial card data returns nil")
    func testPartialCardData() {
        // Missing CVV
        #expect(PPSRCard.parseRichTextBlock("CCNUM: 4111111111111111 EXP: 12/25") == nil)

        // Missing expiry
        #expect(PPSRCard.parseRichTextBlock("CCNUM: 4111111111111111 CVV: 123") == nil)

        // Missing card number
        #expect(PPSRCard.parseRichTextBlock("CVV: 123 EXP: 12/25") == nil)
    }

    // MARK: - Case-Insensitive Matching

    @Test("Parse card from lowercase OCR text")
    func testCaseInsensitiveParsing() {
        let text = "ccnum: 4111111111111111 cvv: 123 exp: 12/25"
        let card = PPSRCard.parseRichTextBlock(text)
        #expect(card != nil)
        #expect(card?.number == "4111111111111111")
    }

    @Test("Parse card from mixed-case OCR text")
    func testMixedCaseParsing() {
        let text = "Ccnum: 4111111111111111 Cvv: 123 Exp: 12/25"
        let card = PPSRCard.parseRichTextBlock(text)
        #expect(card != nil)
        #expect(card?.number == "4111111111111111")
    }

    // MARK: - Expiry Date Parsing

    @Test("Parse various expiry date formats")
    func testExpiryDateFormats() {
        let text1 = "CCNUM: 4111111111111111 CVV: 123 EXP: 12/25"
        let card1 = PPSRCard.parseRichTextBlock(text1)
        #expect(card1?.expiryMonth == "12")
        #expect(card1?.expiryYear == "25")

        let text2 = "CCNUM: 4111111111111111 CVV: 123 EXP: 12-2025"
        let card2 = PPSRCard.parseRichTextBlock(text2)
        #expect(card2?.expiryMonth == "12")
        #expect(card2?.expiryYear == "25")
    }

    // MARK: - CVV Validation

    @Test("CVV length validation")
    func testCVVLength() {
        // 3-digit CVV
        let text1 = "CCNUM: 4111111111111111 CVV: 123 EXP: 12/25"
        let card1 = PPSRCard.parseRichTextBlock(text1)
        #expect(card1?.cvv.count == 3)

        // 4-digit CVV (Amex)
        let text2 = "CCNUM: 371449635398431 CVV: 1234 EXP: 12/25"
        let card2 = PPSRCard.parseRichTextBlock(text2)
        #expect(card2?.cvv.count == 4)
    }

    // MARK: - Thread Safety

    @Test("Concurrent card brand detection")
    func testConcurrentBrandDetection() async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    let brand = CardBrand.detect("4111111111111111")
                    #expect(brand == .visa)
                }
            }
        }
    }

    // MARK: - Memory Safety

    @Test("Large text parsing doesn't crash")
    func testLargeTextParsing() {
        let largeText = String(repeating: "Invalid data ", count: 10000)
        let card = PPSRCard.parseRichTextBlock(largeText)
        #expect(card == nil)
    }

    // MARK: - Edge Cases

    @Test("Card number with invalid characters")
    func testInvalidCharactersInCardNumber() {
        let text = "CCNUM: 4111abc1111111111 CVV: 123 EXP: 12/25"
        let card = PPSRCard.parseRichTextBlock(text)
        // Should filter out non-numeric characters
        #expect(card == nil || card?.number == "4111111111111111")
    }

    @Test("Multiple cards in text - first one wins")
    func testMultipleCardsInText() {
        let text = """
        CCNUM: 4111111111111111 CVV: 123 EXP: 12/25
        CCNUM: 5111111111111111 CVV: 456 EXP: 11/26
        """
        let card = PPSRCard.parseRichTextBlock(text)
        #expect(card?.number == "4111111111111111")
    }
}
