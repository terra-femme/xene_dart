#!/bin/bash
# Xene Dart Stack-Specific Security Audit Script

echo "🔍 Starting Xene Dart Security Audit..."

# 1. Check for hardcoded Supabase Secrets
echo "Checking for hardcoded Supabase keys..."
grep -rnE "SUPABASE_SERVICE_KEY|SUPABASE_URL|anon_key" . --exclude-dir={.git,node_modules,build,.dart_tool} | grep -v ".env.example"
if [ $? -eq 0 ]; then
    echo "⚠️ WARNING: Potential hardcoded Supabase secrets found!"
else
    echo "✅ No hardcoded Supabase secrets detected."
fi

# 2. Check for insecure Supabase client initialization
echo "Checking for insecure Supabase client patterns..."
grep -rn "Supabase.initialize" . --exclude-dir={.git,node_modules,build,.dart_tool}
echo "Verify that RLS is enabled on all tables in your Supabase dashboard."

# 3. Check for Melos monorepo consistency
echo "Checking Melos configuration..."
if [ -f "melos.yaml" ] || grep -q "^melos:" pubspec.yaml; then
    echo "✅ Melos configuration found."
else
    echo "❌ ERROR: Melos configuration missing (no melos.yaml or 'melos:' in pubspec.yaml)!"
fi

# 4. Check for unencrypted .env files
echo "Checking for unencrypted environment files..."
find . -name ".env" -not -path "*/node_modules/*" -not -path "*/build/*"
if [ $? -eq 0 ]; then
    echo "⚠️ WARNING: .env files found. Ensure they are in .gitignore!"
fi

echo "🚀 Audit Complete."
