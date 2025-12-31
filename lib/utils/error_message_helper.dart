class ErrorMessageHelper {
  /// Converts technical error messages to user-friendly messages
  static String getUserFriendlyError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    // Authentication errors
    if (errorString.contains('invalid login credentials') ||
        errorString.contains('invalid credentials') ||
        errorString.contains('invalid_credentials')) {
      return 'Invalid email or password. Please check and try again.';
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
      return 'Network connection error. Please check your internet connection and try again.';
    }
    
    // Database errors
    if (errorString.contains('postgresterror') || errorString.contains('database')) {
      return 'A database error occurred. Please try again later.';
    }
    
    // Permission errors
    if (errorString.contains('permission') || errorString.contains('policy') || errorString.contains('access denied')) {
      return 'You do not have permission to perform this action.';
    }
    
    // Generic errors
    if (errorString.contains('error') && errorString.contains(':')) {
      // Try to extract a meaningful message
      final parts = errorString.split(':');
      if (parts.length > 1) {
        final message = parts.last.trim();
        // Skip if it looks too technical
        if (!message.contains('exception') && 
            !message.contains('statuscode') && 
            !message.contains('code:') &&
            message.length < 100) {
          return message[0].toUpperCase() + message.substring(1);
        }
      }
    }
    
    // Default friendly message
    return 'Something went wrong. Please try again later.';
  }
}

