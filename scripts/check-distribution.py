#!/usr/bin/env python3
"""Verify the installable contents, architecture, signatures and Finder layout."""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
from zipfile import ZipFile

from ds_store import DSStore

parser = argparse.ArgumentParser()
parser.add_argument('--universal', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
output = root / 'temp' / 'outputs'
app = output / 'Sumbar.app'
license_data = (root / 'LICENSE').read_bytes()


def verify_binary(binary):
    architectures = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
    if args.universal:
        assert set(architectures) == {'arm64', 'x86_64'}, architectures
    build_info = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(binary)], text=True)
    minimums = re.findall(r'minos\s+(\d+)\.(\d+)', build_info)
    assert len(minimums) == len(architectures)
    assert all((int(major), int(minor)) <= (14, 0) for major, minor in minimums), build_info


def verify_app(path):
    assert (path / 'Contents/Resources/LICENSE').read_bytes() == license_data
    metadata = plistlib.loads((path / 'Contents/Info.plist').read_bytes())
    assert metadata['CFBundleIdentifier'] == 'uz.sumbar.desktop'
    assert metadata['LSMinimumSystemVersion'] == '14.0'
    assert metadata['CFBundleURLTypes'][0]['CFBundleURLSchemes'] == ['sumbar']
    assert (path / 'Contents/Resources/Sumbar.icns').is_file()
    resources = path / 'Contents/Resources/Sumbar_Sumbar.bundle/Contents/Resources'
    for language in ('ru', 'uz'):
        assert (resources / f'{language}.lproj/Localizable.strings').is_file()
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(path)], check=True)
    binary = path / 'Contents/MacOS/Sumbar'
    verify_binary(binary)
    widget = path / 'Contents/PlugIns/SumbarWidgets.appex'
    info = plistlib.loads((widget / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'uz.sumbar.desktop.widgets'
    assert info['CFBundleShortVersionString'] == metadata['CFBundleShortVersionString']
    assert info['CFBundleVersion'] == metadata['CFBundleVersion']
    assert info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
    verify_binary(widget / 'Contents/MacOS/SumbarWidgets')
    entitlements = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(widget)], stderr=subprocess.DEVNULL))
    assert entitlements['com.apple.security.app-sandbox'] is True
    assert entitlements['com.apple.security.network.client'] is True
    widget_resources = widget / 'Contents/Resources'
    assert (widget_resources / 'Metadata.appintents/extract.actionsdata').is_file()
    for language in ('ru', 'uz'):
        assert (widget_resources / f'{language}.lproj/Localizable.strings').is_file()
    return hashlib.sha256(binary.read_bytes()).digest()


binary_digest = verify_app(app)
with ZipFile(output / 'Sumbar-macOS.zip') as archive:
    assert archive.read('Sumbar.app/Contents/Resources/LICENSE') == license_data
    assert hashlib.sha256(archive.read('Sumbar.app/Contents/MacOS/Sumbar')).digest() == binary_digest
    widget_binary = 'Sumbar.app/Contents/PlugIns/SumbarWidgets.appex/Contents/MacOS/SumbarWidgets'
    assert archive.read(widget_binary) == (output / widget_binary).read_bytes()
for line in (output / 'SHA256SUMS').read_text().splitlines():
    digest, filename = line.split()
    assert hashlib.sha256((output / filename).read_bytes()).hexdigest() == digest
subprocess.run(['hdiutil', 'verify', str(output / 'Sumbar.dmg')], check=True, stdout=subprocess.DEVNULL)
with tempfile.TemporaryDirectory(prefix='sumbar-dmg-', dir=root / 'temp') as folder:
    mount = Path(folder) / 'volume'; mount.mkdir()
    subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(output / 'Sumbar.dmg')], check=True, stdout=subprocess.DEVNULL)
    try:
        assert verify_app(mount / 'Sumbar.app') == binary_digest
        assert os.readlink(mount / 'Программы') == '/Applications'
        with DSStore.open(str(mount / '.DS_Store'), 'r') as store:
            assert store['Sumbar.app']['Iloc'] == (160, 245)
            assert store['Программы']['Iloc'] == (480, 245)
            assert store['.']['bwsp']['ShowToolbar'] is False
            assert store['.']['icvp']['iconSize'] == 88
        assert list(mount.glob('.background*')), 'Missing installer background'
    finally:
        subprocess.run(['hdiutil', 'detach', str(mount)], check=True, stdout=subprocess.DEVNULL)
print('Verified app, ZIP, DMG, Applications link, Finder icon layout, signatures, translations and SHA-256 checksums.')
