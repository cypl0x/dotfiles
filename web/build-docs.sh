#!/usr/bin/env bash
# Build documentation from markdown files

set -euo pipefail

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCS_SRC="$PROJECT_ROOT/docs"
DOCS_OUT="$SCRIPT_DIR/docs"
TEMPLATE="$SCRIPT_DIR/docs-template.html"

echo "Building documentation..."
echo "Source: $DOCS_SRC"
echo "Output: $DOCS_OUT"

# Clean and create output directory
rm -rf "$DOCS_OUT"
mkdir -p "$DOCS_OUT"

# Copy static assets if they exist
if [ -d "$SCRIPT_DIR/static" ]; then
    cp "$SCRIPT_DIR/static/favicon.svg" "$DOCS_OUT/" 2>/dev/null || true
    cp "$SCRIPT_DIR/static/logo.svg" "$DOCS_OUT/" 2>/dev/null || true
fi

# Create index page with list of all docs
cat > "$DOCS_OUT/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Documentation - Wolfhard</title>
    <link rel="icon" type="image/svg+xml" href="/favicon.svg">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            line-height: 1.6;
            color: #e0e0e0;
            background: linear-gradient(135deg, #0f0f0f 0%, #1a1a1a 100%);
            min-height: 100vh;
            padding: 2rem 1rem;
        }
        .container {
            max-width: 900px;
            margin: 0 auto;
            background: rgba(30, 30, 30, 0.95);
            padding: 3rem;
            border-radius: 12px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
        }
        h1 {
            color: #fff;
            margin-bottom: 0.5rem;
            font-size: 2.5rem;
            border-bottom: 3px solid #4a9eff;
            padding-bottom: 0.5rem;
        }
        .subtitle {
            color: #999;
            margin-bottom: 2rem;
            font-size: 1.1rem;
        }
        .doc-list {
            list-style: none;
            margin-top: 2rem;
        }
        .doc-item {
            margin-bottom: 1rem;
            padding: 1.5rem;
            background: rgba(40, 40, 40, 0.8);
            border-radius: 8px;
            border-left: 4px solid #4a9eff;
            transition: all 0.3s ease;
        }
        .doc-item:hover {
            background: rgba(50, 50, 50, 0.9);
            transform: translateX(5px);
            border-left-color: #6bb6ff;
        }
        .doc-item a {
            color: #4a9eff;
            text-decoration: none;
            font-size: 1.3rem;
            font-weight: 600;
            display: block;
        }
        .doc-item a:hover {
            color: #6bb6ff;
        }
        .doc-item .description {
            color: #aaa;
            margin-top: 0.5rem;
            font-size: 0.95rem;
        }
        .footer {
            margin-top: 3rem;
            text-align: center;
            color: #666;
            font-size: 0.9rem;
        }
        .footer a {
            color: #4a9eff;
            text-decoration: none;
        }
        .footer a:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>📚 Documentation</h1>
        <p class="subtitle">System configuration and reference guides</p>

        <ul class="doc-list">
EOF

# Generate index entries for each markdown file
for md_file in "$DOCS_SRC"/*.md; do
    if [ -f "$md_file" ]; then
        filename=$(basename "$md_file" .md)
        html_file="$filename.html"

        # Get the first heading from the markdown file as title
        title=$(grep -m 1 "^# " "$md_file" | sed 's/^# //' || echo "$filename")

        # Get the second line as description if it exists
        description=$(sed -n '2p' "$md_file" | sed 's/^[#> ]*//' || echo "")

        cat >> "$DOCS_OUT/index.html" <<EOF
            <li class="doc-item">
                <a href="$html_file">$title</a>
                <div class="description">$description</div>
            </li>
EOF
    fi
done

cat >> "$DOCS_OUT/index.html" <<'EOF'
        </ul>

        <div class="footer">
            <p>Generated from <a href="https://github.com/cypl0x/dotfiles">cypl0x/dotfiles</a></p>
            <p>© 2025 Wolfhard Prell</p>
        </div>
    </div>
</body>
</html>
EOF

# Convert each markdown file to HTML using pandoc
for md_file in "$DOCS_SRC"/*.md; do
    if [ -f "$md_file" ]; then
        filename=$(basename "$md_file" .md)
        html_file="$DOCS_OUT/$filename.html"

        echo "Converting $filename.md -> $filename.html"

        # Get title from first heading
        title=$(grep -m 1 "^# " "$md_file" | sed 's/^# //' || echo "$filename")

        pandoc "$md_file" \
            --from markdown \
            --to html5 \
            --standalone \
            --template="$TEMPLATE" \
            --metadata title="$title" \
            --metadata pagetitle="$title - Documentation" \
            --toc \
            --toc-depth=3 \
            --output="$html_file"
    fi
done

echo "✓ Documentation build complete!"
echo "Generated $(find "$DOCS_OUT" -name "*.html" | wc -l) HTML files"
