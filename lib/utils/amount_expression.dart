/// Arithmetic typed into an amount field: `250+80`, `1200/3`, `(450+90)*2`.
///
/// Splitting a bill or adding up a receipt used to mean leaving the form for
/// a calculator. Accepts + - * / (also × ÷ and x), brackets, a leading minus
/// and the digit grouping amounts are shown with ("1,250"). Returns null for
/// anything that is not a complete sum, including a division by zero.
double? evaluateAmountExpression(String input) {
  final text = input
      .replaceAll(RegExp(r'[,\s]'), '')
      .replaceAll('×', '*')
      .replaceAll('x', '*')
      .replaceAll('X', '*')
      .replaceAll('÷', '/')
      .replaceAll('−', '-');
  if (text.isEmpty || text.length > 200) return null;
  final parser = _Parser(text);
  final value = parser.expression();
  if (value == null || !parser.atEnd || !value.isFinite) return null;
  return value;
}

/// Whether [input] holds an operator between figures, so it is a sum to work
/// out rather than a plain amount (a lone leading minus does not count).
bool isAmountExpression(String input) =>
    RegExp(r'[0-9.)]\s*[+\-*/×÷xX−]').hasMatch(input);

/// Recursive descent over `expression := term (('+'|'-') term)*`,
/// `term := factor (('*'|'/') factor)*`, `factor := '-' factor | '(' expression ')' | number`.
class _Parser {
  final String s;
  int i = 0;
  int _depth = 0;
  _Parser(this.s);

  bool get atEnd => i == s.length;

  double? expression() {
    var left = _term();
    if (left == null) return null;
    while (!atEnd && (s[i] == '+' || s[i] == '-')) {
      final op = s[i++];
      final right = _term();
      if (right == null) return null;
      left = op == '+' ? left! + right : left! - right;
    }
    return left;
  }

  double? _term() {
    var left = _factor();
    if (left == null) return null;
    while (!atEnd && (s[i] == '*' || s[i] == '/')) {
      final op = s[i++];
      final right = _factor();
      if (right == null) return null;
      if (op == '/' && right == 0) return null;
      left = op == '*' ? left! * right : left! / right;
    }
    return left;
  }

  double? _factor() {
    if (atEnd) return null;
    // Bounded, so a pasted run of brackets or minus signs cannot overflow
    // the stack.
    if (_depth > 32) return null;
    if (s[i] == '-') {
      i++;
      _depth++;
      final v = _factor();
      _depth--;
      return v == null ? null : -v;
    }
    if (s[i] == '(') {
      i++;
      _depth++;
      final v = expression();
      _depth--;
      if (v == null || atEnd || s[i] != ')') return null;
      i++;
      return v;
    }
    final start = i;
    while (!atEnd && RegExp(r'[0-9.]').hasMatch(s[i])) {
      i++;
    }
    if (i == start) return null;
    return double.tryParse(s.substring(start, i));
  }
}
