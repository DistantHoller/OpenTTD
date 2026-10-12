#!/usr/bin/env python3
from pathlib import Path
import plistlib
import sys

Path(sys.argv[1]).write_bytes(plistlib.dumps({
    "CFBundleDevelopmentRegion": "English",
    "CFBundleDisplayName": "OpenTTD Modern",
    "CFBundleName": "OpenTTD Modern",
    "CFBundleExecutable": "openttd",
    "CFBundleIdentifier": "org.openttd.modern.local",
    "CFBundleIconFile": "openttd.icns",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "0.2.0",
    "CFBundleVersion": "2",
    "LSMinimumSystemVersion": "14.0",
    "LSApplicationCategoryType": "public.app-category.simulation-games",
    "NSHighResolutionCapable": True,
    "NSPrincipalClass": "NSApplication",
    "NSHumanReadableCopyright": "OpenTTD contributors. Modern presentation additions 2026. GPLv2.",
}))
