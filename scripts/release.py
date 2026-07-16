#!/usr/bin/env python3
"""
Mac Trackpad Fix release script.
Builds .pkg, signs it with Sparkle, uploads to Google Drive (stable file IDs),
updates appcast.xml in-place, commits and pushes.

Usage:
    python3 scripts/release.py 2.0.1 "Bug fix release"
    python3 scripts/release.py 2.1.0 "New feature" --no-rebuild
"""
import argparse, io, os, re, subprocess, sys, warnings
from pathlib import Path

warnings.filterwarnings('ignore')

REPO_ROOT   = Path(__file__).parent.parent.resolve()
SCRIPTS_DIR = REPO_ROOT / 'scripts'
sys.path.insert(0, str(SCRIPTS_DIR))

# Reuse Lux's OAuth infrastructure
LUX_SCRIPTS = Path('/Users/virgoh/lux/scripts')
sys.path.insert(0, str(LUX_SCRIPTS))

from constants import (
    GDRIVE_FOLDER_ID, LUX_OAUTH_CLIENT, LUX_TOKEN_CACHE,
    APPCAST_FILE_ID, PKG_FILE_ID, PKG_URL, APPCAST_URL, PKG_BASENAME,
)

SPARKLE_BIN = REPO_ROOT / '.build/artifacts/sparkle/Sparkle/bin/sign_update'
INFOPLIST   = REPO_ROOT / 'MacTrackpadFix/Resources/Info.plist'
APPCAST_XML = REPO_ROOT / 'appcast.xml'

# ── Helpers ────────────────────────────────────────────────────────────────────

def run(cmd, **kw):
    print(f'  $ {cmd}')
    return subprocess.run(cmd, shell=True, check=True, **kw)

def get_version():
    text = INFOPLIST.read_text()
    m = re.search(r'<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>', text)
    return m.group(1) if m else '0.0.0'

def bump_version(version, notes, build_increment=1):
    """Bump CFBundleShortVersionString and CFBundleVersion in Info.plist."""
    text = INFOPLIST.read_text()
    # Bump short version
    text = re.sub(
        r'(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)',
        rf'\g<1>{version}\g<2>', text
    )
    # Bump build number
    def inc_build(m):
        return m.group(1) + str(int(m.group(2)) + build_increment) + m.group(3)
    text = re.sub(
        r'(<key>CFBundleVersion</key>\s*<string>)(\d+)(</string>)',
        inc_build, text
    )
    INFOPLIST.write_text(text)
    print(f'  ✓ Info.plist bumped to {version}')

def sparkle_sign(pkg_path):
    """Run sign_update and return (signature, length)."""
    result = subprocess.run(
        [str(SPARKLE_BIN), str(pkg_path)],
        capture_output=True, text=True
    )
    output = result.stdout + result.stderr
    sig_m  = re.search(r'edSignature="([^"]+)"', output)
    len_m  = re.search(r'length="(\d+)"', output)
    if not sig_m or not len_m:
        print(f'sign_update output: {output}')
        raise RuntimeError('Could not parse Sparkle signature')
    return sig_m.group(1), int(len_m.group(1))

def gdrive_service():
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from google.auth.transport.requests import Request
    from googleapiclient.discovery import build
    import requests as _req

    # Reuse Lux's proxy/SSL patch
    from release import _patch_ssl_and_proxy
    proxy = _patch_ssl_and_proxy()
    sess = _req.Session()
    sess.verify = False
    sess.proxies = {'http': proxy, 'https': proxy}

    SCOPES = ['https://www.googleapis.com/auth/drive']
    creds = None
    token_path = str(LUX_TOKEN_CACHE)
    if Path(token_path).exists():
        creds = Credentials.from_authorized_user_file(token_path, SCOPES)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request(sess))
        else:
            flow = InstalledAppFlow.from_client_secrets_file(str(LUX_OAUTH_CLIENT), SCOPES)
            creds = flow.run_local_server(port=0)
        Path(token_path).write_text(creds.to_json())
    return build('drive', 'v3', credentials=creds)

def upload_overwrite(service, file_id, local_path, mime='application/octet-stream'):
    from googleapiclient.http import MediaFileUpload
    media = MediaFileUpload(str(local_path), mimetype=mime, resumable=True)
    f = service.files().update(fileId=file_id, media_body=media, fields='id,name,size').execute()
    print(f'  ↻ Updated {Path(local_path).name} (id={f["id"]}, size={int(f.get("size",0))//1024}KB)')
    return f['id']

def upload_xml_overwrite(service, file_id, xml_path):
    from googleapiclient.http import MediaIoBaseUpload
    with open(xml_path, 'rb') as f:
        content = f.read()
    media = MediaIoBaseUpload(io.BytesIO(content), mimetype='text/xml')
    f = service.files().update(fileId=file_id, media_body=media, fields='id,name').execute()
    print(f'  ↻ Updated appcast.xml (id={f["id"]})')

def update_appcast_xml(version, signature, length, notes):
    """Prepend a new item to appcast.xml (GitHub version — uses GitHub release URLs)."""
    text = APPCAST_XML.read_text()

    build_m = re.search(
        r'<key>CFBundleVersion</key>\s*<string>(\d+)</string>',
        INFOPLIST.read_text()
    )
    build = build_m.group(1) if build_m else '0'

    from datetime import datetime, timezone
    pubdate = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000')

    github_url = f'https://github.com/miguelAngelo1999/trackpad-volume-knob/releases/download/v{version}/MacTrackpadFix-{version}.pkg'

    new_item = f'''    <item>
      <title>Version {version}</title>
      <pubDate>{pubdate}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>Mac Trackpad Fix {version}</h2>
        <p>{notes}</p>
      ]]></description>
      <enclosure
        url="{github_url}"
        length="{length}"
        type="application/x-newton-compatible-pkg"
        sparkle:edSignature="{signature}"
      />
    </item>

'''
    text = text.replace('    <item>', new_item + '    <item>', 1)
    APPCAST_XML.write_text(text)
    print(f'  ✓ appcast.xml (GitHub) updated for {version}')

    # Also generate the Drive version of appcast.xml (same but with Drive pkg URL)
    drive_text = text.replace(github_url, PKG_URL)
    drive_appcast = REPO_ROOT / 'appcast_drive.xml'
    drive_appcast.write_text(drive_text)
    print(f'  ✓ appcast_drive.xml (Drive) updated for {version}')
    return drive_appcast

# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description='Mac Trackpad Fix release')
    ap.add_argument('version', nargs='?', default='', help='New version e.g. 2.1.0')
    ap.add_argument('notes',   nargs='?', default='', help='Release notes')
    ap.add_argument('--no-rebuild', action='store_true', help='Skip swift build')
    ap.add_argument('--dry-run',    action='store_true', help='No upload, no push')
    args = ap.parse_args()

    version = args.version or get_version()
    notes   = args.notes   or f'Mac Trackpad Fix {version}'
    pkg_name = PKG_BASENAME.format(version=version)
    pkg_path = REPO_ROOT / pkg_name

    print(f'\n🚀 Mac Trackpad Fix {version}')

    # 1. Bump version in Info.plist
    bump_version(version, notes)

    # 2. Build
    if not args.no_rebuild:
        print('\n── Building ────────────────────────────────────────────────────')
        run(f'swift build -c release', cwd=REPO_ROOT)
        run(f'bash {SCRIPTS_DIR}/assemble_app.sh', cwd=REPO_ROOT)

    # 3. Build pkg
    print('\n── Building pkg ────────────────────────────────────────────────')
    run(f'bash {SCRIPTS_DIR}/build_pkg.sh {version}', cwd=REPO_ROOT)
    assert pkg_path.exists(), f'{pkg_path} not found'

    # 4. Sign with Sparkle
    print('\n── Signing with Sparkle ────────────────────────────────────────')
    signature, length = sparkle_sign(pkg_path)
    print(f'  edSignature={signature}')
    print(f'  length={length}')

    # 5. Update appcast.xml
    print('\n── Updating appcast.xml ────────────────────────────────────────')
    drive_appcast = update_appcast_xml(version, signature, length, notes)

    if args.dry_run:
        print('\n✅ Dry run — skipping upload and push.')
        return

    # 6. Upload to Google Drive (stable file IDs)
    print('\n── Uploading to Google Drive ───────────────────────────────────')
    service = gdrive_service()
    upload_overwrite(service, PKG_FILE_ID, pkg_path, 'application/x-newton-compatible-pkg')
    upload_xml_overwrite(service, APPCAST_FILE_ID, drive_appcast)  # Drive version has Drive pkg URL

    # 7. Upload pkg to GitHub Releases too (for old users on GitHub appcast)
    print('\n── Uploading to GitHub Releases ────────────────────────────────')
    run(f'env -u HTTPS_PROXY -u HTTP_PROXY gh release create v{version} {pkg_path} --title "Mac Trackpad Fix {version}" --notes "{notes}" 2>&1 || env -u HTTPS_PROXY -u HTTP_PROXY gh release upload v{version} {pkg_path} 2>&1', cwd=REPO_ROOT)

    # 8. Commit and push GitHub appcast
    print('\n── Committing ──────────────────────────────────────────────────')
    run(f'git add appcast.xml MacTrackpadFix/Resources/Info.plist', cwd=REPO_ROOT)
    run(f'git commit -m "v{version}: {notes}"', cwd=REPO_ROOT)
    run(f'env -u HTTPS_PROXY -u HTTP_PROXY git push', cwd=REPO_ROOT)

    print(f'\n✅ Mac Trackpad Fix {version} released!')
    print(f'   PKG URL:     {PKG_URL}')
    print(f'   Appcast URL: {APPCAST_URL}')
    print(f'\n   Next release: python3 scripts/release.py 2.x.x "release notes"')

if __name__ == '__main__':
    main()
