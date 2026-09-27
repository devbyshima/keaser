#if DEBUG
import Foundation

/// A receipt's text as text recognition returns it, line by line, with what
/// a person reading it would fill in. DEBUG only: the tests, the model
/// evaluation and New Expense's `-KeaserReceipt` screenshots share them.
public struct ReceiptSample: Sendable {
    public let name: String
    public let lines: [String]
    public let expected: ReceiptDraft

    init(_ name: String, merchant: String?, total: String?, day: ReceiptDay?, currency: String? = nil, _ text: String) {
        self.name = name
        self.lines = text.split(separator: "\n").map(String.init)
        let total = total.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        self.expected = ReceiptDraft(merchant: merchant, total: total, day: day, currencyCode: currency)
    }
}

/// Receipts from the places Keaser is used: US shops and restaurants,
/// French, German, Spanish, Italian and Dutch ones with decimal commas,
/// British pounds, Rwandan francs without decimals, Japanese yen, and a ride
/// receipt; totals next to subtotals, tax, tips, savings, cash and change;
/// dates in every common order.
public enum ReceiptSamples {
    /// The day the samples are read on; none of their dates is after it.
    public static let today = day(2026, 9, 27)

    public static func named(_ name: String) -> ReceiptSample? {
        all.first { $0.name == name }
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> ReceiptDay {
        ReceiptDay(year: year, month: month, day: day)!
    }

    public static let all: [ReceiptSample] = [
        ReceiptSample("grocery", merchant: "Trader Joe's", total: "12.50", day: day(2026, 9, 21), """
        TRADER JOE'S
        1234 Market St
        San Francisco, CA 94103
        (415) 555-0123
        BANANAS 0.99
        ORGANIC MILK 4.49
        SOURDOUGH BREAD 3.99
        DARK CHOCOLATE 2.49
        SUBTOTAL 11.96
        TAX 0.54
        TOTAL $12.50
        VISA ****1234 $12.50
        09/21/2026 14:32
        THANK YOU FOR SHOPPING
        """),
        ReceiptSample("coffee", merchant: "Blue Bottle Coffee", total: "11.43", day: day(2026, 9, 26), """
        BLUE BOTTLE COFFEE
        66 Mint St
        San Francisco, CA 94103
        Order #4471  Register 2
        Sep 26, 2026 8:04 AM
        Oat Latte 6.25
        Almond Croissant 4.25
        Subtotal $10.50
        Tax $0.93
        Total $11.43
        Apple Pay $11.43
        """),
        ReceiptSample("restaurant-tip", merchant: "The Mission Taco Bar", total: "31.61", day: day(2026, 9, 25), """
        THE MISSION TACO BAR
        2150 Mission St
        San Francisco CA 94110
        Server: Maria Table 12
        Guests: 2
        09/25/26 8:14 PM
        2 Carnitas Tacos 9.00
        1 Guacamole & Chips 7.50
        2 Horchata 8.00
        Subtotal 24.50
        Tax 8.625% 2.11
        Total 26.61
        Tip 5.00
        Total 31.61
        MASTERCARD ****4821 31.61
        Thank you!
        """),
        ReceiptSample("pharmacy", merchant: "CVS/pharmacy", total: "13.48", day: day(2026, 8, 30), """
        CVS/pharmacy
        Store 8842
        1100 Broadway, New York, NY 10010
        (212) 555-0199
        ADVIL 24CT 8.99
        CVS VITAMIN D3 6.49
        EXTRACARE SAVINGS -2.00
        SUBTOTAL 13.48
        NY TAX 8.875% 0.00
        TOTAL 13.48
        TOTAL SAVINGS 2.00
        VISA CREDIT 13.48
        RETURNS WITH RECEIPT BY 11/24/2026
        08/30/2026 10:02 AM
        """),
        ReceiptSample("drugstore", merchant: "Walgreens", total: "7.98", day: day(2026, 3, 8), """
        WALGREENS #3341
        300 Castro St
        Mountain View, CA 94041
        03/08/2026 1:15 PM
        TISSUES 2PK 4.49
        LIP BALM 3.49
        TOTAL 7.98
        DEBIT 7.98
        """),
        ReceiptSample("gas", merchant: "Shell", total: "52.81", day: day(2026, 9, 24), """
        SHELL
        4501 El Camino Real
        Palo Alto, CA 94306
        SEP 24, 2026 07:12 AM
        PUMP # 06
        UNLEADED
        GALLONS 11.482
        PRICE/GAL $4.599
        FUEL TOTAL $52.81
        TOTAL $52.81
        DEBIT $52.81
        """),
        ReceiptSample("starbucks", merchant: "Starbucks", total: "10.22", day: day(2026, 9, 26), """
        STARBUCKS STORE #05123
        1 Ferry Building
        San Francisco, CA
        CHK 8841
        9/26/2026 07:58 AM
        Grande Latte 5.45
        Butter Croissant 3.95
        Subtotal $9.40
        Tax $0.82
        Total $10.22
        Visa $10.22
        Join our loyalty program
        """),
        ReceiptSample("logo", merchant: "Target", total: "17.98", day: day(2026, 9, 19), """
        2025 El Camino Real
        Mountain View, CA 94040
        (650) 555-0100
        Paper Towels 12.99
        Dish Soap 3.49
        Subtotal 16.48
        CA Tax 9.125% 1.50
        Total 17.98
        MasterCard 17.98
        09/19/2026 17:22
        Thank you for shopping at Target
        """),
        ReceiptSample("food-truck", merchant: "Joe's Food Truck", total: "13.50", day: nil, """
        Joe's Food Truck
        Burrito 11.00
        Soda 2.50
        Card 13.50
        Thanks!
        """),
        ReceiptSample("ride", merchant: "Uber", total: "23.47", day: day(2026, 9, 22), """
        Uber
        Thanks for riding, Alex
        September 22, 2026
        Total $23.47
        Trip fare $18.20
        Booking Fee $2.75
        Tip $2.52
        Payments
        Visa ••••4242 $23.47
        """),
        ReceiptSample("cafe-paris", merchant: "Café de Flore", total: "14.50", day: day(2026, 4, 3), currency: "EUR", """
        Café de Flore
        172 Boulevard Saint-Germain
        75006 Paris
        Tél 01 45 48 55 26
        Table 14 Couverts 2
        03/04/2026 09:12
        2 Café crème 11,00
        1 Croissant 3,50
        Total HT 13,18
        TVA 10% 1,32
        Total TTC 14,50 €
        CB 14,50
        Merci de votre visite
        """),
        ReceiptSample("supermarket-berlin", merchant: "REWE Markt", total: "6.02", day: day(2026, 9, 21), currency: "EUR", """
        REWE Markt GmbH
        Friedrichstraße 123
        10117 Berlin
        UID Nr.: DE812706034
        EUR
        Bio Vollmilch 3,5% 1,29 B
        Bananen 1,99 B
        Roggenbrot 2,49 B
        Pfand 0,25 A
        SUMME EUR 6,02
        Geg. BAR EUR 10,00
        Rückgeld EUR 3,98
        MwSt 7% 0,39
        Datum: 21.09.2026 Uhrzeit: 18:45:12
        Vielen Dank für Ihren Einkauf
        """),
        ReceiptSample("cafe-madrid", merchant: "Cafetería El Sol", total: "7.50", day: day(2026, 9, 26), currency: "EUR", """
        CAFETERÍA EL SOL
        C/ Mayor 12, 28013 Madrid
        NIF: B12345678
        FACTURA SIMPLIFICADA
        Fecha: 26-09-2026 Hora: 10:31
        1 Café con leche 1,80
        1 Tostada con tomate 2,50
        1 Zumo de naranja 3,20
        Base imponible 6,82
        IVA 10% 0,68
        TOTAL A PAGAR 7,50 €
        Tarjeta 7,50
        ¡Gracias por su visita!
        """),
        ReceiptSample("bar-rome", merchant: "Bar Pasticceria Rossi", total: "2.70", day: day(2026, 9, 20), """
        BAR PASTICCERIA ROSSI
        Via Roma 15 - 00184 Roma
        P.IVA 01234567890
        DOCUMENTO COMMERCIALE
        di vendita o prestazione
        Caffè 1,20
        Cornetto 1,50
        TOTALE COMPLESSIVO 2,70
        di cui IVA 0,24
        Pagamento contante 5,00
        Resto 2,30
        20-09-2026 08:05
        Grazie e arrivederci
        """),
        ReceiptSample("supermarket-amsterdam", merchant: "Albert Heijn", total: "8.43", day: day(2026, 9, 5), """
        Albert Heijn
        Damrak 70, Amsterdam
        Tel 020-1234567
        Melk 1,15
        Kaas 4,79
        Appels 2,49
        Totaal 8,43
        Pinnen 8,43
        BTW 9% 0,70
        05-09-26 16:20
        Bedankt en tot ziens
        """),
        ReceiptSample("pub-london", merchant: "The Red Lion", total: "39.99", day: day(2026, 9, 12), currency: "GBP", """
        THE RED LION
        48 Parliament Street
        London SW1A 2NH
        VAT No. 123 4567 89
        Date: 12 Sep 2026 Time: 21:03
        2 x Pint of Pride 11.80
        1 x Fish & Chips 16.50
        1 x Sticky Toffee 7.25
        Subtotal 35.55
        Service 12.5% 4.44
        Total £39.99
        Card Payment £39.99
        Thank you, see you soon
        """),
        ReceiptSample("supermarket-kigali", merchant: "Simba Supermarket", total: "6300", day: day(2026, 9, 14), currency: "RWF", """
        SIMBA SUPERMARKET LTD
        KN 4 Ave, Kigali
        Tel: 0788 300 400
        TIN: 101234567
        Date: 14/09/2026 18:05
        Inyange Milk 1L 1,500
        Bread 1,200
        Eggs x12 3,600
        TOTAL RWF 6,300
        CASH 10,000
        CHANGE 3,700
        Murakoze! Thank you
        """),
        ReceiptSample("market-kigali", merchant: "Kimironko Fresh Market", total: "3000", day: day(2026, 8, 28), currency: "RWF", """
        Kimironko Fresh Market
        Tomatoes 2kg 1,200
        Onions 800
        Avocado x4 1,000
        3,000 Frw
        28/08/2026
        """),
        ReceiptSample("konbini-tokyo", merchant: "FamilyMart", total: "753", day: day(2026, 9, 20), """
        FamilyMart
        Shibuya Dogenzaka Store
        Tel 03-1234-5678
        2026/09/20 07:48
        Onigiri Salmon ¥160
        Green Tea ¥140
        Sandwich ¥398
        Subtotal ¥698
        Tax (8%) ¥55
        Total ¥753
        Cash ¥1,000
        Change ¥247
        """),
        ReceiptSample("not-a-receipt", merchant: "Meeting notes", total: nil, day: nil, """
        Meeting notes
        Call Sam about the budget
        Book the venue
        """),
    ]
}
#endif
