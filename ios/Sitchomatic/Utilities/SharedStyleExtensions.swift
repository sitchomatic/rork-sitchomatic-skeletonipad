import SwiftUI

// MARK: - PPSRLogEntry.Level Color

extension PPSRLogEntry.Level {
    var color: Color {
        switch self {
        case .info: .blue
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}

// MARK: - CardBrand Display Color

extension CardBrand {
    var displayColor: Color {
        switch self {
        case .visa: .blue
        case .mastercard: .orange
        case .amex: .green
        case .jcb: .red
        case .discover: .purple
        case .dinersClub: .indigo
        case .unionPay: .teal
        case .unknown: .secondary
        }
    }
}

// MARK: - CredentialStatus Color

extension CredentialStatus {
    var color: Color {
        switch self {
        case .working: .green
        case .noAcc: .red
        case .permDisabled: .purple
        case .tempDisabled: .orange
        case .unsure: .yellow
        case .untested: .gray
        case .testing: .blue
        }
    }
}

// MARK: - CardStatus Color

extension CardStatus {
    var color: Color {
        switch self {
        case .working: .green
        case .dead: .red
        case .testing: .teal
        case .untested: .secondary
        }
    }
}
