import 'package:flutter/material.dart';

/// The icon an account of [type] wears, wherever it is shown.
IconData accountTypeIcon(String type) {
  switch (type) {
    case 'cash':
      return Icons.payments;
    case 'bank':
      return Icons.account_balance;
    case 'upi':
      return Icons.qr_code;
    case 'credit_card':
      return Icons.credit_card;
    case 'loan':
      return Icons.request_quote_outlined;
    case 'lent':
      return Icons.handshake_outlined;
    default:
      return Icons.account_balance_wallet;
  }
}
