import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_colors.dart';
import '../utils/error_message_helper.dart';

class OtpVerificationWidget extends StatefulWidget {
  final String email;
  final VoidCallback onVerified;
  final String title;
  final String subtitle;

  const OtpVerificationWidget({
    super.key,
    required this.email,
    required this.onVerified,
    this.title = 'Enter Verification Code',
    this.subtitle = 'We sent a verification code to your email',
  });

  @override
  State<OtpVerificationWidget> createState() => _OtpVerificationWidgetState();
}

class _OtpVerificationWidgetState extends State<OtpVerificationWidget> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.email,
        email: widget.email,
        token: _otpController.text.trim(),
      );

      if (response.session != null) {
        // OTP verified successfully
        if (mounted) {
          widget.onVerified();
        }
      } else {
        throw Exception('OTP verification failed');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        final friendlyMessage = ErrorMessageHelper.getUserFriendlyError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _resendOtp() async {
    setState(() {
      _isResending = true;
    });

    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: widget.email,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification code sent! Please check your email.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final friendlyMessage = ErrorMessageHelper.getUserFriendlyError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            widget.subtitle,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            widget.email,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _otpController,
            decoration: InputDecoration(
              labelText: 'Verification Code',
              hintText: 'Enter 8-digit code',
              hintStyle: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: AppColors.textSecondary,
              ),
              prefixIcon: const Icon(Icons.lock_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            keyboardType: TextInputType.number,
            maxLength: 8,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              letterSpacing: 8,
              fontWeight: FontWeight.bold,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter verification code';
              }
              if (value.length != 8) {
                return 'Code must be 8 digits';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _verifyOtp,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Verify Code',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _isResending ? null : _resendOtp,
            child: _isResending
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Resend Code'),
          ),
        ],
      ),
    );
  }
}

