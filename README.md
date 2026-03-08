# credilo

A comprehensive Flutter mobile application for managing daily financial operations across multiple business branches. Built with Supabase backend, featuring role-based access control, real-time data synchronization, and comprehensive financial tracking.

## Overview

Built by ZyntelX, credilo helps businesses track and manage their daily financial operations including sales, expenses, cash flow, dues, and supplier management. The app supports multi-branch operations with granular role-based permissions, ensuring data security and proper access control.

## Features

### Core Financial Management
- **Cash Expenses**: Track daily cash expenses with categories and notes
- **Credit Expenses**: Manage supplier credit purchases with payment status tracking
- **Cash Balance**: Record cash counts by denomination with automatic total calculation
- **Card Sales**: Track card machine transactions with TID and machine management
- **Online Sales**: Record e-commerce platform sales with commission tracking
- **QR/UPI Payments**: Track digital payment transactions
- **Dues Management**: Manage receivables and payables with due dates and status
- **Cash Closing**: Daily cash closing with opening balance, sales, expenses, and discrepancy tracking

### Multi-Branch Support
- Manage multiple branches per business
- Branch-specific financial tracking
- Aggregate reporting across branches
- Branch status management (active/inactive)

### Role-Based Access Control
- **Business Owner**: Full access to all branches and features, can manage users
- **Business Owner (Read-Only)**: Read-only access to all branches, cannot manage users
- **Owner**: Full access to assigned branches
- **Owner (Read-Only)**: Read-only access to assigned branches
- **Manager**: Can edit today and yesterday's data
- **Staff**: Can only edit today's data
- Date-based permission system prevents unauthorized edits
- Pending user invitations with automatic account provisioning

### Supplier Management
- Add, edit, and delete suppliers
- Track credit expenses by supplier
- Payment status tracking (paid/unpaid)
- Supplier-wise expense reports

### Analytics & Reporting
- **Owner Dashboard**: Comprehensive analytics for business owners
- **Daily Summary**: Today's sales, expenses, and net profit
- **Date Range Reports**: Custom date range analysis
- **Branch Comparison**: Compare performance across branches
- **Dues Overview**: Track receivables and payables

### User Management
- OTP-based authentication (email verification)
- User registration and authentication
- Role assignment per branch
- User profile management
- Branch-user relationship management
- Pending user invitations with automatic role assignment
- User-friendly error messages

## Tech Stack

- **Framework**: Flutter 3.10+
- **Language**: Dart
- **Backend**: Supabase (PostgreSQL + Real-time)
- **State Management**: Provider
- **Local Database**: SQLite (sqflite) for offline support
- **UI**: Material Design 3 (Dark Theme)
- **Date Handling**: intl
- **Utilities**: uuid

## Architecture

### Service Layer
- **AuthService**: Handles authentication, user management, and role-based permissions
- **DatabaseService**: Manages all database operations and data synchronization

### Model Layer
- Business, Branch, User, BranchUser
- Financial models: CashExpense, CreditExpense, CashCount, CardSale, OnlineSale, QrPayment, Due, CashClosing
- Supplier model

### Screen Layer
- Authentication: Login/Registration (unified flow)
- Dashboard: Home, Owner Dashboard, Financial Entry
- Financial Operations: Cash Expense, Credit Expense, Cash Balance, Card Sales, Online Sales, QR Payments, Dues, Cash Closing
- Management: Branch Management, Supplier Management, User Management, Card Machine Management
- Settings: Profile, Settings

### Widget Layer
- Reusable components: BranchSelector, DateSelector
- Utility widgets: DeleteConfirmationDialog

## Project Structure

```
lib/
├── config/
│   └── supabase_config.dart          # Supabase configuration
├── models/                            # Data models
│   ├── business.dart
│   ├── branch.dart
│   ├── user.dart
│   ├── branch_user.dart
│   ├── cash_expense.dart
│   ├── credit_expense.dart
│   ├── cash_count.dart
│   ├── card_sale.dart
│   ├── online_sale.dart
│   ├── qr_payment.dart
│   ├── due.dart
│   ├── cash_closing.dart
│   └── supplier.dart
├── screens/                           # UI screens
│   ├── login_screen.dart              # Unified login/registration
│   ├── dashboard_home_screen.dart
│   ├── home_screen.dart              # Financial entry screen
│   ├── owner_dashboard_screen.dart
│   ├── cash_expense_screen.dart
│   ├── credit_expense_screen.dart
│   ├── cash_balance_screen.dart
│   ├── card_screen.dart
│   ├── online_sales_screen.dart
│   ├── qr_payment_screen.dart
│   ├── due_screen.dart
│   ├── cash_closing_screen.dart
│   ├── supplier_management_screen.dart
│   ├── user_management_screen.dart
│   └── ...
├── services/
│   ├── auth_service.dart             # Authentication & authorization
│   └── database_service.dart         # Database operations
├── utils/
│   ├── app_colors.dart               # Color scheme
│   ├── currency_formatter.dart       # Currency formatting
│   ├── date_range_utils.dart         # Date utilities
│   └── delete_confirmation_dialog.dart
├── widgets/
│   ├── branch_selector.dart
│   └── date_selector.dart
└── main.dart                         # App entry point
```

## Getting Started

### Prerequisites

- Flutter SDK 3.10.0 or higher
- Dart SDK
- Supabase account
- Android Studio / Xcode (for mobile development)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd credilo
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Set up Supabase**
   - Create your Supabase project at [supabase.com](https://supabase.com)
   - Go to SQL Editor in your Supabase dashboard
   - Run the entire `supabase_schema.sql` file to create all tables, functions, triggers, and RLS policies
   - Get your Supabase URL and anon key from Settings → API

4. **Configure Supabase**
   - Update `lib/config/supabase_config.dart` with your Supabase credentials:
   ```dart
   class SupabaseConfig {
     static const String supabaseUrl = 'YOUR_SUPABASE_URL';
     static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
   }
   ```

5. **Configure Email Templates (Optional)**
   - Go to Authentication → Email Templates in Supabase dashboard
   - Update the OTP email template to use 8-digit codes (see `EMAIL_TEMPLATE_8DIGIT.html` for reference)

6. **Run the app**
   ```bash
   flutter run
   ```

## Key Concepts

### Branch-User Relationship
Users are assigned to branches through the `branch_users` table with specific roles:
- Each user can have different roles in different branches
- Roles determine what actions a user can perform
- Business owners have access to all branches in their business

### Date-Based Permissions
- **Staff**: Can only view/edit today's data
- **Manager**: Can view/edit today and yesterday's data
- **Owner/Business Owner**: Can view/edit any date

### Cash Closing Flow
1. Record opening balance (from previous day's closing)
2. Track cash sales (calculated from cash counts)
3. Record all expenses
4. Count cash at end of day
5. Calculate discrepancy
6. Set next day's opening balance

### Credit Expenses
- Track purchases from suppliers on credit
- Mark expenses as paid/unpaid
- Filter and manage by supplier
- Track payment status over time

## Usage

### First Time Setup
1. Login with your email (OTP-based authentication)
2. If new user, complete registration with business details
3. Create your first branch
4. Start recording daily financial operations

### Daily Operations
1. Select a branch from the dashboard
2. Choose the date (subject to role permissions)
3. Record financial entries:
   - Cash expenses
   - Credit expenses
   - Cash balance counts
   - Card sales
   - Online sales
   - QR/UPI payments
   - Dues (receivables/payables)
4. Complete cash closing at end of day

### Managing Suppliers
1. Navigate to Supplier Management (Business Owner only)
2. Add supplier details
3. Record credit expenses linked to suppliers
4. Track payment status and manage dues

### Viewing Reports
1. Access Owner Dashboard (Business Owner/Owner only)
2. Select date range
3. Choose branches to analyze
4. View aggregated sales, expenses, and profit data

## Development

### Code Style
- Follow Dart/Flutter style guidelines
- Use meaningful variable and function names
- Add comments for complex logic
- Maintain consistent formatting

### Adding New Features
1. Create model in `lib/models/`
2. Add database methods in `lib/services/database_service.dart`
3. Create screen in `lib/screens/`
4. Update navigation and permissions as needed

### Testing
```bash
flutter test
```

### Building for Production

**Android:**
```bash
flutter build apk --release
# or
flutter build appbundle --release
```

**iOS:**
```bash
flutter build ios --release
```

## Configuration

### Supabase Setup
1. Create a Supabase project at [supabase.com](https://supabase.com)
2. Go to SQL Editor and run the entire `supabase_schema.sql` file (this creates all tables, functions, triggers, and RLS policies)
3. Get your project URL and anon key from Settings → API
4. Update `lib/config/supabase_config.dart` with your credentials
5. Configure email templates in Authentication → Email Templates (optional: use the 8-digit OTP template from `EMAIL_TEMPLATE_8DIGIT.html` for better UX)

### Where keys and secrets are stored

| Secret | Location | In repo? |
|--------|----------|----------|
| **Supabase URL & anon key** | `lib/config/supabase_config.dart` | Yes (replace with your own; consider env for production) |
| **Android signing** | `android/key.properties` (passwords, alias, storeFile path) | No (in `.gitignore`) |
| **Android keystore** | `android/app/upload-keystore.jks` (or path in `key.properties`) | No (in `.gitignore`) |

There are **no `.env` or environment variables** used by the app at build or runtime. Supabase is configured in code; Android release signing reads `android/key.properties` at build time. For production, consider loading Supabase credentials from CI secrets or a secure config (e.g. `flutter_dotenv` + `.env` not committed) instead of hardcoding.

## Security Considerations

- Row Level Security (RLS) should be configured in Supabase
- User authentication handled by Supabase Auth
- Role-based permissions enforced at app level
- Date-based edit restrictions prevent unauthorized modifications
- Branch-level data isolation

## Troubleshooting

### Common Issues

**Supabase connection errors:**
- Verify Supabase URL and anon key in `supabase_config.dart`
- Check network connectivity
- Ensure Supabase project is active

**Permission errors:**
- Verify user role in `branch_users` table
- Check RLS policies in Supabase
- Ensure user is assigned to the branch

**Data not syncing:**
- Check Supabase connection
- Verify database service methods
- Check for error logs in console

## App Store (iOS) Release

### Prerequisites

- **Apple Developer Program** membership (team: Zyntel X / PA83972LRU)
- **App Store Connect**: Agreements signed (Business), Tax & Banking if offering paid/IAP
- **Certificates, Identifiers & Profiles**: App ID registered for `com.zyntelx.credilo`
- **Devices**: At least one physical iOS device registered (required for automatic signing until first distribution profile exists)

### Build & Upload

1. **Open in Xcode** (use the workspace, not the project):
   ```bash
   open ios/Runner.xcworkspace
   ```
2. **Select destination**: **Any iOS Device (arm64)** (not a simulator).
3. **Archive**: **Product → Archive**.
4. **Distribute**: In Organizer → select the archive → **Distribute App** → **App Store Connect** → **Upload**.

### App Store Connect Checklist

- **App Information**: Primary category = **Finance** (required). Secondary optional (e.g. Business).
- **Version metadata**: Description, keywords, Support URL, Copyright, screenshots (min 3 for 6.5" iPhone).
- **App Review**: Sign-in required; use test account (see below). Contact info (name, phone, email) and Notes for OTP.
- **App Privacy**: Declare data collection (e.g. Name, Email, Phone if collected, Other Financial Info, User ID). Purpose: App functionality; not used for tracking.
- **Age Rating**: Complete all 7 steps (Features, Mature Themes, Medical, Sexuality, Violence, Chance-Based, Additional). For Credilo: all NO/NONE → typically **4+**.
- **Pricing and Availability**: Set price (e.g. Free) and availability.
- **Encryption**: If prompted, choose **None** (only standard HTTPS/TLS).
- **Content Rights**: No third-party content → select "No".

### Test Account for App Review

- **Email**: `test@credilo.app`
- **Verification code (OTP)**: `87654321` (no email needed; app uses password sign-in for this account only)
- Ensure this user exists in Supabase Auth with **password** set to `87654321` (e.g. via Supabase Dashboard or Auth Admin API / SQL update to `auth.users`).

### iOS-Specific Notes

- **iPad multitasking**: `ios/Runner/Info.plist` must include all four orientations for iPad (`UISupportedInterfaceOrientations~ipad`): Portrait, PortraitUpsideDown, LandscapeLeft, LandscapeRight. Missing landscape causes upload validation failure.
- **Bundle ID**: Must match App ID in developer account (`com.zyntelx.credilo`).
- **Team**: Xcode project uses `DEVELOPMENT_TEAM = PA83972LRU` (Zyntel X).

### After Upload

- Build appears in App Store Connect under the app version after processing (often 5–30 min).
- Select the build for the version → **Add for Review** → **Submit for Review**.

---

## Android (Google Play) Release

### Signing key (important)

Release builds for Play Store must be signed with a **keystore**. If you lose the keystore or its passwords, you **cannot** publish updates to the same app on Play Store.

**1. Create the keystore (one-time)**

From project root:
```bash
cd android/app
./create_keystore.sh
```
Or use `create_keystore_auto.sh` for non-interactive creation (passwords are generated and written to `android/keystore_passwords.txt`).

This creates:
- **Keystore file**: `android/app/upload-keystore.jks` (or the path you chose)
- **Passwords**: You set store password and key password; save them securely.

**2. `key.properties` (do not commit)**

Create or update `android/key.properties` (this file is in `.gitignore`):

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=upload-keystore.jks
```

- `storeFile` is relative to `android/app/` (e.g. `upload-keystore.jks` if the keystore is in `android/app/`).
- Without `key.properties`, release builds fall back to debug signing and are not accepted by Play Store.

**3. Build release bundle for Play Store**

```bash
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`. Upload this in Google Play Console.

**4. Backup (critical)**

- Back up `upload-keystore.jks` and the store/key passwords in a secure place (e.g. password manager or secure storage).
- Do **not** commit `key.properties` or `*.jks` to version control.

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

[Add your license here]

## Support

For issues and questions:
- Check the documentation
- Review the Supabase setup section above for backend configuration
- Check Supabase dashboard for database issues

---

**Version**: 1.1.3+5  
**Last Updated**: 2024
