#!/bin/bash

# Auto-create keystore with generated secure passwords

cd "$(dirname "$0")"

# Check if keystore already exists
if [ -f "upload-keystore.jks" ]; then
    echo "Keystore already exists at: $(pwd)/upload-keystore.jks"
    echo "If you want to recreate it, delete it first: rm upload-keystore.jks"
    exit 1
fi

# Generate secure random passwords
STORE_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
KEY_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

echo "=========================================="
echo "Creating Android Signing Keystore"
echo "=========================================="
echo ""
echo "Generating secure passwords..."
echo "Creating keystore with auto-generated passwords..."
echo ""

# Create keystore with non-interactive mode
keytool -genkey -v \
    -keystore upload-keystore.jks \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -alias upload \
    -storepass "$STORE_PASSWORD" \
    -keypass "$KEY_PASSWORD" \
    -dname "CN=Credilo, OU=Development, O=ZyntelX, L=Unknown, ST=Unknown, C=US" \
    -noprompt

if [ $? -eq 0 ]; then
    echo "✓ Keystore created successfully!"
    echo ""
    
    # Update key.properties
    key_props_file="../key.properties"
    cat > "$key_props_file" << EOF
storePassword=$STORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=upload
storeFile=upload-keystore.jks
EOF
    
    echo "✓ key.properties updated with passwords"
    echo ""
    echo "=========================================="
    echo "IMPORTANT: SAVE THESE PASSWORDS!"
    echo "=========================================="
    echo ""
    echo "Keystore Password: $STORE_PASSWORD"
    echo "Key Password: $KEY_PASSWORD"
    echo ""
    echo "These passwords have been saved to:"
    echo "  - android/key.properties (for builds)"
    echo ""
    echo "BACKUP YOUR KEYSTORE:"
    echo "  Location: $(pwd)/upload-keystore.jks"
    echo ""
    echo "If you lose the keystore or passwords, you CANNOT update"
    echo "your app on Play Store. Keep a secure backup!"
    echo ""
    
    # Save passwords to a secure file (outside of git)
    passwords_file="../keystore_passwords.txt"
    cat > "$passwords_file" << EOF
CREDILO ANDROID KEYSTORE PASSWORDS
===================================
Generated: $(date)
Keystore: upload-keystore.jks
Location: android/app/upload-keystore.jks

STORE PASSWORD: $STORE_PASSWORD
KEY PASSWORD: $KEY_PASSWORD
KEY ALIAS: upload

IMPORTANT: Keep this file secure and backed up!
If you lose these, you cannot update your app on Play Store.
EOF
    
    echo "Passwords also saved to: android/keystore_passwords.txt"
    echo "(This file is NOT in git - keep it secure!)"
    echo ""
    echo "You can now build your release bundle:"
    echo "  flutter build appbundle --release"
else
    echo "Error: Failed to create keystore"
    exit 1
fi

