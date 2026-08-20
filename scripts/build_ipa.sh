#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-${PROJECT_ROOT}/xSpese.xcodeproj}"
SCHEME="${SCHEME:-xSpese}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-xSpese}"
DIST_DIR="${DIST_DIR:-${PROJECT_ROOT}/dist}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-${PROJECT_ROOT}/build/ipa-derived-data}"

fail() {
    echo "Errore: $*" >&2
    exit 1
}

require_project_subdirectory() {
    local path="$1"
    case "${path}" in
        "${PROJECT_ROOT}"/*) ;;
        *) fail "il percorso deve essere interno al progetto: ${path}" ;;
    esac
    [[ "${path}" != "${PROJECT_ROOT}" ]] || fail "rifiutata operazione sulla radice del progetto"
}

command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild non è disponibile"
command -v python3 >/dev/null 2>&1 || fail "python3 non è disponibile"
command -v zip >/dev/null 2>&1 || fail "zip non è disponibile"
[[ -d "${PROJECT_PATH}" ]] || fail "progetto Xcode non trovato: ${PROJECT_PATH}"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

require_project_subdirectory "${DIST_DIR}"
require_project_subdirectory "${DERIVED_DATA_DIR}"

rm -rf "${DIST_DIR}" "${DERIVED_DATA_DIR}"
mkdir -p "${DIST_DIR}" "${DERIVED_DATA_DIR}"

echo "Build senza firma Apple di ${APP_NAME} (${CONFIGURATION})…"
xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -derivedDataPath "${DERIVED_DATA_DIR}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    clean build

APP_PATH="${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}-iphoneos/${APP_NAME}.app"
INFO_PLIST="${APP_PATH}/Info.plist"
WIDGET_PATH="${APP_PATH}/PlugIns/xSpeseWidgets.appex"
MAIN_ENTITLEMENTS="${PROJECT_ROOT}/xSpese/xSpese.entitlements"
WIDGET_ENTITLEMENTS="${PROJECT_ROOT}/xSpeseWidgets/xSpeseWidgets.entitlements"
[[ -d "${APP_PATH}" ]] || fail "bundle .app non trovato: ${APP_PATH}"
[[ -f "${INFO_PLIST}" ]] || fail "Info.plist compilato non trovato"
[[ -f "${APP_PATH}/${APP_NAME}" ]] || fail "eseguibile principale non trovato"
[[ -d "${WIDGET_PATH}" ]] || fail "estensione widget non trovata: ${WIDGET_PATH}"

# La firma ad-hoc non rende l'IPA installabile direttamente, ma conserva gli
# entitlement nel Mach-O. SideStore può così rilevare e ricreare lo stesso App
# Group quando firma app ed estensione con il certificato dell'utente.
/usr/bin/codesign --force --sign - --timestamp=none --generate-entitlement-der \
    --entitlements "${WIDGET_ENTITLEMENTS}" "${WIDGET_PATH}"
/usr/bin/codesign --force --sign - --timestamp=none --generate-entitlement-der \
    --entitlements "${MAIN_ENTITLEMENTS}" "${APP_PATH}"
/usr/bin/codesign --verify --deep --strict "${APP_PATH}"

MAIN_EXTRACTED_ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/xspese-main-entitlements.XXXXXX")"
WIDGET_EXTRACTED_ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/xspese-widget-entitlements.XXXXXX")"
/usr/bin/codesign -d --entitlements "${MAIN_EXTRACTED_ENTITLEMENTS}" --xml "${APP_PATH}" 2>/dev/null
/usr/bin/codesign -d --entitlements "${WIDGET_EXTRACTED_ENTITLEMENTS}" --xml "${WIDGET_PATH}" 2>/dev/null

python3 - "${MAIN_EXTRACTED_ENTITLEMENTS}" "${WIDGET_EXTRACTED_ENTITLEMENTS}" <<'PY'
import plistlib
import sys

expected = "group.it.alessandroiacca.xSpese"
for path in sys.argv[1:]:
    with open(path, "rb") as stream:
        entitlements = plistlib.load(stream)
    groups = entitlements.get("com.apple.security.application-groups", [])
    if expected not in groups:
        raise SystemExit(f"App Group mancante negli entitlement estratti da {path}: {groups}")
print(f"App Group verificato su app e widget: {expected}")
PY

/bin/rm -f "${MAIN_EXTRACTED_ENTITLEMENTS}" "${WIDGET_EXTRACTED_ENTITLEMENTS}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST}")"

[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || \
    fail "MARKETING_VERSION non è semantic versioning: ${VERSION}"

if [[ -n "${EXPECTED_VERSION:-}" && "${VERSION}" != "${EXPECTED_VERSION}" ]]; then
    fail "il tag richiede ${EXPECTED_VERSION}, ma Xcode dichiara ${VERSION}"
fi

PACKAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/xspese-ipa.XXXXXX")"
trap 'rm -rf "${PACKAGE_DIR}"' EXIT
mkdir -p "${PACKAGE_DIR}/Payload"
/usr/bin/ditto "${APP_PATH}" "${PACKAGE_DIR}/Payload/${APP_NAME}.app"

IPA_NAME="${APP_NAME}-${VERSION}.ipa"
IPA_PATH="${DIST_DIR}/${IPA_NAME}"
(
    cd "${PACKAGE_DIR}"
    /usr/bin/zip -qry -y "${IPA_PATH}" Payload
)

[[ -s "${IPA_PATH}" ]] || fail "IPA non creato"
/usr/bin/unzip -tq "${IPA_PATH}" >/dev/null || fail "l'IPA non è uno ZIP valido"
/usr/bin/unzip -l "${IPA_PATH}" | grep -q "Payload/${APP_NAME}.app/Info.plist" || \
    fail "l'IPA non contiene Payload/${APP_NAME}.app/Info.plist"

python3 - "${IPA_PATH}" "${DIST_DIR}/build-info.json" "${APP_NAME}" "${VERSION}" "${BUILD_NUMBER}" "${BUNDLE_IDENTIFIER}" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

ipa_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
payload = {
    "name": sys.argv[3],
    "version": sys.argv[4],
    "build": sys.argv[5],
    "bundleIdentifier": sys.argv[6],
    "ipa": ipa_path.name,
    "size": ipa_path.stat().st_size,
    "sha256": hashlib.sha256(ipa_path.read_bytes()).hexdigest(),
    "signed": False,
    "signature": "ad-hoc (entitlements preserved for SideStore)",
}
output_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY

echo "IPA creato: ${IPA_PATH}"
echo "Metadati: ${DIST_DIR}/build-info.json"
echo "Nota: l'IPA ha una firma ad-hoc e deve essere rifirmato dal metodo di installazione."
