#!/bin/bash

# Ensure the script receives two arguments
if [[ $# -lt 2 ]]; then
	echo "Usage: $0 <library_name> <new_version>"
	exit 1
fi

LIBRARY_NAME="$1"
NEW_VERSION="$2"
SUCCESSFUL_UPDATES=0

echo "Updating '$LIBRARY_NAME' to version '$NEW_VERSION' in all package.json files..."

# Function to check and install jq if missing
install_jq() {
	if ! command -v jq &> /dev/null; then
		echo "⚠️  jq is not installed but required for running this scrip. Do you want to install it? (y/n)"
		read -r answer
		if [[ "$answer" =~ ^[Yy]$ ]]; then
			if [[ "$OSTYPE" == "linux-gnu"* ]]; then
				sudo apt-get update && sudo apt-get install -y jq || sudo yum install -y jq || sudo dnf install -y jq
			elif [[ "$OSTYPE" == "darwin"* ]]; then
				brew install jq
			else
				echo "❌ Unsupported OS. Install jq manually."
				exit 1
			fi
		else
			echo "❌ jq is required to run this script. Exiting..."
			exit 1
		fi
	fi
}

# Ensure jq is installed before running the script
install_jq

# Find all package.json files in the monorepo (excluding node_modules)
PACKAGE_JSON_FILES=$(find . -type f -name "package.json" -not -path "*/node_modules/*")
PACKAGE_COUNT=$(echo "$PACKAGE_JSON_FILES" | wc -l)

# Loop through each package.json file and update/add the override
for file in $PACKAGE_JSON_FILES; do
	echo "Checking $file"

	# Read the current indentation style (detects tabs or spaces)
	INDENTATION=$(grep -Eo '^\s+' "$file" | head -n 1)
	if [[ "$INDENTATION" == *$'\t'* ]]; then
		JQ_INDENT="--tab"  # Preserve tabs if used
	else
		JQ_INDENT="--indent 4"  # Default to 4 spaces
	fi

	# Ensure "pnpm" section exists without modifying existing content
	if ! jq -e '.pnpm' "$file" > /dev/null; then
		echo "  ➕ Adding 'pnpm' section to $file"
		jq "$JQ_INDENT" '. + { "pnpm": { "overrides": {} } }' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
	fi

	# Ensure "overrides" section exists inside "pnpm" without modifying anything else
	if ! jq -e '.pnpm.overrides' "$file" > /dev/null; then
		echo "  🔄 Updating / adding 'overrides' section to $file"
		jq "$JQ_INDENT" '.pnpm += { "overrides": {} }' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
	fi

	# Update or add the library override inside "pnpm.overrides"
	jq "$JQ_INDENT" --arg lib "$LIBRARY_NAME" --arg version "$NEW_VERSION" \
	   '.pnpm.overrides[$lib] = $version' "$file" > "$file.tmp" && mv "$file.tmp" "$file"

	((SUCCESSFUL_UPDATES++)) # Increment success counter

	echo "✅ Updated $file"
done

echo "" # Empty line
echo "✨ $SUCCESSFUL_UPDATES of $PACKAGE_COUNT package.json files have been updated!"
