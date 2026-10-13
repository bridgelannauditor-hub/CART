/// Reusable form-field validators, shared across auth and profile
/// screens so the rules (and their messages) stay consistent in one
/// place instead of being copy-pasted per screen.
class Validators {
  Validators._();

  static String? name(String? value, {String label = "This field"}) {
    if (value == null || value.trim().isEmpty) {
      return "$label is required";
    }
    if (value.trim().length < 2) {
      return "Minimum 2 characters";
    }
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "Email is required";
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
      return "Enter a valid email";
    }
    return null;
  }

  static String? schoolEmail(String? value) {
    final basicError = email(value);
    if (basicError != null) return basicError;
    final domain = value!.trim().toLowerCase().split('@').last;
    if (!domain.endsWith('.edu.ph')) {
      return 'Use your official school email ending in .edu.ph';
    }
    return null;
  }

  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "Mobile number is required";
    }
    if (!RegExp(r'^09\d{9}$').hasMatch(value.trim())) {
      return "Enter a valid PH mobile number";
    }
    return null;
  }

  /// Same as [phone] but blank is allowed (optional field).
  static String? optionalPhone(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return phone(value);
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return "Password is required";
    }
    if (value.length < 8) {
      return "Password must be at least 8 characters";
    }
    return null;
  }

  static String? required(String? value, {String label = "This field"}) {
    if (value == null || value.trim().isEmpty) {
      return "$label is required";
    }
    return null;
  }
}
