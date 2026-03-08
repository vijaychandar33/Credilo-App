#!/bin/bash

# Script to create Android signing keystore for Credilo app

echo "=========================================="
echo "Creating Android Signing Keystore"
echo "=========================================="
echo ""
echo "This will create a keystore file for signing your app for Play Store."
echo "You'll need to provide:"
echo "  - A strong password for the keystore (save this!)"
echo "  - A strong password for the key (save this!)"
echo "  - Your name/organization details"
echo ""
echo "IMPORTANT: Save these passwords securely. You'll need them for all future updates!"
echo ""

# Navigate to the app directory
cd "$(dirname "$0")"

# Check if keystore already exists
if [ -f "upload-keystore.jks" ]; then
    echo "WARNING: upload-keystore.jks already exists!"
    read -p "Do you want to overwrite it? (yes/no): " overwrite
    if [ "$overwrite" != "yes" ]; then
        echo "Aborted. Existing keystore preserved."
        exit 1
    fi
    rm upload-keystore.jks
fi

# Prompt for keystore password
echo ""
read -sp "Enter keystore password (min 6 chars): " store_password
echo ""
if [ ${#store_password} -lt 6 ]; then
    echo "Error: Password must be at least 6 characters"
    exit 1
fi

read -sp "Confirm keystore password: " store_password_confirm
echo ""
if [ "$store_password" != "$store_password_confirm" ]; then
    echo "Error: Passwords don't match"
    exit 1
fi

# Prompt for key password
echo ""
read -sp "Enter key password (min 6 chars, can be same as keystore): " key_password
echo ""
if [ ${#key_password} -lt 6 ]; then
    echo "Error: Password must be at least 6 characters"
    exit 1
fi

read -sp "Confirm key password: " key_password_confirm
echo ""
if [ "$key_password" != "$key_password_confirm" ]; then
    echo "Error: Passwords don't match"
    exit 1
fi

# Prompt for certificate details
echo ""
echo "Now enter certificate details (press Enter to use defaults):"
read -p "Your first and last name [Credilo Developer]: " name
name=${name:-Credilo Developer}

read -p "Organizational unit [Development]: " org_unit
org_unit=${org_unit:-Development}

read -p "Organization [ZyntelX]: " org
org=${org:-ZyntelX}

read -p "City or Locality: " city
city=${city:-Unknown}

read -p "State or Province: " state
state=${state:-Unknown}

read -p "Two-letter country code [US]: " country
country=${country:-US}

# Create the keystore
echo ""
echo "Creating keystore..."
keytool -genkey -v \
    -keystore upload-keystore.jks \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -alias upload \
    -storepass "$store_password" \
    -keypass "$key_password" \
    -dname "CN=$name, OU=$org_unit, O=$org, L=$city, ST=$state, C=$country"

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✓ Keystore created successfully!"
    echo "=========================================="
    echo ""
    echo "Keystore location: $(pwd)/upload-keystore.jks"
    echo ""
    echo "Now updating key.properties file..."
    
    # Update key.properties
    key_props_file="../key.properties"
    if [ -f "$key_props_file" ]; then
        # Create backup
        cp "$key_props_file" "$key_props_file.backup"
        
        # Update with actual passwords
        cat > "$key_props_file" << EOF
storePassword=$store_password
keyPassword=$key_password
keyAlias=upload
storeFile=upload-keystore.jks
EOF
        echo "✓ key.properties updated"
        echo ""
        echo "IMPORTANT SECURITY NOTES:"
        echo "  - key.properties contains your passwords in plain text"
        echo "  - It's already in .gitignore, so it won't be committed"
        echo "  - Keep your keystore file (upload-keystore.jks) backed up securely"
        echo "  - If you lose the keystore, you CANNOT update your app on Play Store"
        echo ""
        echo "You're all set! You can now build your release bundle with:"
        echo "  flutter build appbundle --release"
    else
        echo "Warning: key.properties file not found at $key_props_file"
        echo "Please manually update it with:"
        echo "  storePassword=$store_password"
        echo "  keyPassword=$key_password"
        echo "  keyAlias=upload"
        echo "  storeFile=upload-keystore.jks"
    fi
else
    echo ""
    echo "Error: Failed to create keystore"
    exit 1
fi

