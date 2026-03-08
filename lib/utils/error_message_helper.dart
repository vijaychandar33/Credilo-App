import 'package:flutter/foundation.dart';

class ErrorMessageHelper {
  /// Returns true if the provided text looks like a URL or contains one.
  static bool _looksLikeUrl(String value) {
    final lower = value.toLowerCase();
    return lower.contains('http://') ||
        lower.contains('https://') ||
        RegExp(r'\b[a-z0-9\-]+\.[a-z]{2,}\b').hasMatch(lower);
  }

  /// Converts technical error messages to user-friendly messages
  static String getUserFriendlyError(dynamic error, {bool showDetails = false}) {
    // Log the actual error for debugging
    debugPrint('ErrorMessageHelper: Raw error: $error');
    debugPrint('ErrorMessageHelper: Error runtimeType: ${error.runtimeType}');
    
    // In debug mode, try to extract more details
    if (kDebugMode && error is Exception) {
      debugPrint('ErrorMessageHelper: Exception details: ${error.toString()}');
    }
    
    final errorString = error.toString().toLowerCase();
    
    // Always log technical details for debugging, but never show them to users
    // showDetails parameter is kept for backward compatibility but ignored
    // Technical errors are logged via debugPrint above
    
    // Authentication errors
    if (errorString.contains('invalid login credentials') ||
        errorString.contains('invalid credentials') ||
        errorString.contains('invalid_credentials')) {
      return 'Invalid email or verification code. Please check and try again.';
    }
    
    if (errorString.contains('user_already_exists') ||
        errorString.contains('user already registered') ||
        errorString.contains('already registered')) {
      return 'This email is already registered. Please use a different email or try logging in.';
    }
    
    if (errorString.contains('email not confirmed') ||
        errorString.contains('email_not_confirmed')) {
      return 'Please verify your email address before logging in.';
    }
    
    if (errorString.contains('user not found') ||
        errorString.contains('user_not_found')) {
      return 'No account found with this email address.';
    }
    
    if (errorString.contains('user account has been deactivated')) {
      return 'Your account has been deactivated. Please contact your administrator.';
    }
    
    if (errorString.contains('network') || errorString.contains('connection') || errorString.contains('timeout')) {
      return 'Internet not available. Please check your connection and try again.';
    }
    
    // Rate limiting errors - check for specific OTP rate limit first
    if (errorString.contains('over_email_send_rate_limit') || 
        errorString.contains('email_send_rate_limit') ||
        errorString.contains('email_rate_limit')) {
      // Try to extract wait time from message if available
      final waitTimeMatch = RegExp(r'after (\d+) seconds?', caseSensitive: false).firstMatch(errorString);
      if (waitTimeMatch != null) {
        final seconds = waitTimeMatch.group(1);
        return 'Please wait $seconds seconds before requesting another verification code.';
      }
      return 'Too many verification codes sent. Please wait a moment and try again.';
    }
    
    if (errorString.contains('rate limit') || 
        errorString.contains('too many requests') || 
        errorString.contains('429') ||
        (errorString.contains('security purposes') && errorString.contains('request this after'))) {
      // Try to extract wait time from message if available
      final waitTimeMatch = RegExp(r'after (\d+) seconds?', caseSensitive: false).firstMatch(errorString);
      if (waitTimeMatch != null) {
        final seconds = waitTimeMatch.group(1);
        return 'Please wait $seconds seconds before trying again.';
      }
      return 'Too many requests. Please wait a moment and try again.';
    }
    
    // Email service errors
    if (errorString.contains('email') && (errorString.contains('failed') || errorString.contains('error'))) {
      return 'Failed to send verification email. Please check your email address and try again.';
    }
    
    // Supabase specific errors
    if (errorString.contains('supabase') || errorString.contains('auth')) {
      if (errorString.contains('signup_disabled')) {
        return 'New signups are currently disabled. Please contact support.';
      }
    }
    
    // Database errors
    if (errorString.contains('postgresterror') || errorString.contains('database')) {
      return 'A database error occurred. Please try again later.';
    }
    
    // Permission errors - but check for specific OTP errors first
    if (errorString.contains('invalid') && errorString.contains('token')) {
      return 'Invalid verification code. Please check and try again.';
    }
    
    if (errorString.contains('expired') || errorString.contains('expires')) {
      return 'Verification code has expired. Please request a new code.';
    }
    
    if (errorString.contains('permission') || errorString.contains('policy') || errorString.contains('access denied')) {
      // Log the actual error for debugging
      debugPrint('Permission error detected. Full error: $error');
      return 'You do not have permission to perform this action.';
    }
    
    // Try to extract user-friendly message from AuthApiException and similar exceptions
    // Look for pattern: ExceptionType(message: "user friendly message", ...)
    final messageMatch = RegExp(r'message:\s*([^,}]+)', caseSensitive: false).firstMatch(errorString);
    if (messageMatch != null) {
      final message = messageMatch.group(1)?.trim();
      if (message != null && 
          message.isNotEmpty && 
          message.length < 150 &&
          !message.contains('exception') &&
          !message.contains('statuscode') &&
          !message.contains('code:')) {
        // Clean up the message - remove quotes if present
        String cleanMessage = message;
        if (cleanMessage.startsWith('"') || cleanMessage.startsWith("'")) {
          cleanMessage = cleanMessage.substring(1);
        }
        if (cleanMessage.endsWith('"') || cleanMessage.endsWith("'")) {
          cleanMessage = cleanMessage.substring(0, cleanMessage.length - 1);
        }
        if (cleanMessage.isNotEmpty && !_looksLikeUrl(cleanMessage)) {
          return cleanMessage[0].toUpperCase() + cleanMessage.substring(1);
        }
      }
    }
    
    // Try to extract error message from Supabase exceptions
    if (errorString.contains('postgrest') || errorString.contains('realtime') || errorString.contains('storage')) {
      // Try to find a message after common prefixes
      final messageMatch = RegExp(r'(message|error|detail):\s*([^,}]+)', caseSensitive: false).firstMatch(errorString);
      if (messageMatch != null && messageMatch.groupCount >= 2) {
        final message = messageMatch.group(2)?.trim();
        if (message != null && message.isNotEmpty && message.length < 150) {
          // Clean up the message - remove quotes if present
          String cleanMessage = message;
          if (cleanMessage.startsWith('"') || cleanMessage.startsWith("'")) {
            cleanMessage = cleanMessage.substring(1);
          }
          if (cleanMessage.endsWith('"') || cleanMessage.endsWith("'")) {
            cleanMessage = cleanMessage.substring(0, cleanMessage.length - 1);
          }
          if (cleanMessage.isNotEmpty && 
              !cleanMessage.contains('exception') &&
              !cleanMessage.contains('statuscode') &&
              !cleanMessage.contains('code:') &&
              !_looksLikeUrl(cleanMessage)) {
            return cleanMessage[0].toUpperCase() + cleanMessage.substring(1);
          }
        }
      }
    }
    
    // Generic errors - only extract if it looks user-friendly
    if (errorString.contains('error') && errorString.contains(':')) {
      // Try to extract a meaningful message
      final parts = errorString.split(':');
      if (parts.length > 1) {
        final message = parts.last.trim();
        // Skip if it looks too technical
        if (!message.contains('exception') && 
            !message.contains('statuscode') && 
            !message.contains('code:') &&
            !message.contains('stacktrace') &&
            !message.contains('authapiexception') &&
            message.length < 100 &&
            !_looksLikeUrl(message)) {
          // Clean up the message - remove quotes if present
          String cleanMessage = message;
          if (cleanMessage.startsWith('"') || cleanMessage.startsWith("'")) {
            cleanMessage = cleanMessage.substring(1);
          }
          if (cleanMessage.endsWith('"') || cleanMessage.endsWith("'")) {
            cleanMessage = cleanMessage.substring(0, cleanMessage.length - 1);
          }
          if (cleanMessage.isNotEmpty) {
            return cleanMessage[0].toUpperCase() + cleanMessage.substring(1);
          }
        }
      }
    }
    
    // Default friendly message
    debugPrint('ErrorMessageHelper: Using default error message for: $error');
    return 'Something went wrong. Please check your connection and try again.';
  }
}

