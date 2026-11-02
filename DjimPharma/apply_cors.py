with open('config/settings.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Add corsheaders to INSTALLED_APPS
if 'corsheaders' not in content:
    content = content.replace(
        "'rest_framework',",
        "'corsheaders',\n    'rest_framework',"
    )

# Add CorsMiddleware to MIDDLEWARE
if 'corsheaders.middleware.CorsMiddleware' not in content:
    content = content.replace(
        "'django.middleware.common.CommonMiddleware',",
        "'corsheaders.middleware.CorsMiddleware',\n    'django.middleware.common.CommonMiddleware',"
    )

# Add CORS settings at bottom if not present
if 'CORS_ALLOW_ALL_ORIGINS' not in content:
    cors_config = """
# ── CONFIGURATION CORS POUR FLUTTER WEB & TOUS CLIENTS ──
CORS_ALLOW_ALL_ORIGINS = True
CORS_ALLOW_CREDENTIALS = True
CORS_ALLOWED_ORIGIN_REGEXES = [
    r"^http://localhost:\\d+$",
    r"^http://127\\.0\\.0\\.1:\\d+$",
]
"""
    content += cors_config

with open('config/settings.py', 'w', encoding='utf-8') as f:
    f.write(content)

print('CORS configuration applied successfully to config/settings.py')
