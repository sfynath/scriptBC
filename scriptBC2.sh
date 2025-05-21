#!/bin/bash

# ==========================================
# Step 0: Git Clone Config
# ==========================================
GIT_USERNAME="syarief.hidayatulloh%40compnet.co.id"

read -s -p "Masukkan password untuk Git: " GIT_PASSWORD
echo ""

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <nama_tiket> <git_url> <branch>"
  exit 1
fi

NAMA_TIKET=$1
GIT_URL=$2
BRANCH=$3

GIT_URL_WITH_AUTH=$(echo "$GIT_URL" | sed -E "s#https://#https://${GIT_USERNAME}:${GIT_PASSWORD}@#")

mkdir -p "$NAMA_TIKET" && cd "$NAMA_TIKET" || exit 1

echo "[*] Cloning repository..."
git clone -b "$BRANCH" "$GIT_URL_WITH_AUTH" . || {
  echo "❌ Gagal clone repo"
  exit 1
}

# ==========================================
# Step 1: Maven Build
# ==========================================
if [ -f "pom.xml" ]; then
  echo "[*] Menjalankan mvn clean install..."
  mvn clean install || exit 1
else
  echo "[*] Tidak ditemukan pom.xml"
fi

# ==========================================
# Step 2: SonarQube Scan
# ==========================================
SONAR_URL="http://10.10.10.4:3000"
PROJECT_KEY="$NAMA_TIKET"
TOKEN="919c23b5c5be86d584217490931dbc1576a83ab8"

echo "[*] Menjalankan Sonar Scanner..."
if [ -f "pom.xml" ]; then
  sonar-scanner \
    -Dsonar.projectKey=$PROJECT_KEY \
    -Dsonar.sources=. \
    -Dsonar.java.binaries=. \
    -Dsonar.host.url=$SONAR_URL \
    -Dsonar.login=$TOKEN
else
  sonar-scanner \
    -Dsonar.projectKey=$PROJECT_KEY \
    -Dsonar.sources=. \
    -Dsonar.host.url=$SONAR_URL \
    -Dsonar.login=$TOKEN
fi

# ==========================================
# Step 3: Fetch JSON and Parse Without jq
# ==========================================
echo "[*] Mengambil security_hotspots..."
HOTSPOT_JSON=$(curl -s -u "$TOKEN:" "$SONAR_URL/api/hotspots/search?projectKey=$PROJECT_KEY")

echo "[*] Mengambil issues..."
ISSUE_JSON=$(curl -s -u "$TOKEN:" "$SONAR_URL/api/issues/search?componentKeys=$PROJECT_KEY")

# Count MEDIUM and LOW in security hotspots
MEDIUM_HOTSPOTS=$(echo "$HOTSPOT_JSON" | grep -o '"vulnerabilityProbability":"MEDIUM"' | wc -l)
LOW_HOTSPOTS=$(echo "$HOTSPOT_JSON" | grep -o '"vulnerabilityProbability":"LOW"' | wc -l)

# Count severities in issues
BLOCKER_ISSUES=$(echo "$ISSUE_JSON" | grep -o '"severity":"BLOCKER"' | wc -l)
CRITICAL_ISSUES=$(echo "$ISSUE_JSON" | grep -o '"severity":"CRITICAL"' | wc -l)
MAJOR_ISSUES=$(echo "$ISSUE_JSON" | grep -o '"severity":"MAJOR"' | wc -l)

# ==========================================
# Step 4: Decision Logic
# ==========================================
echo "============================="
echo "🔎 Ringkasan Hasil Analisis:"
echo "MEDIUM Security Hotspots : $MEDIUM_HOTSPOTS"
echo "LOW Security Hotspots    : $LOW_HOTSPOTS"
echo "BLOCKER Issues           : $BLOCKER_ISSUES"
echo "CRITICAL Issues          : $CRITICAL_ISSUES"
echo "MAJOR Issues             : $MAJOR_ISSUES"
echo "============================="

if [ "$MEDIUM_HOTSPOTS" -gt 0 ]; then
  echo "❌ HASIL: TIDAK LULUS ISSUE (Ada Hotspot MEDIUM)"
elif [ "$LOW_HOTSPOTS" -gt 0 ] && ( [ "$BLOCKER_ISSUES" -gt 0 ] || [ "$CRITICAL_ISSUES" -gt 0 ] || [ "$MAJOR_ISSUES" -gt 0 ] ); then
  echo "⚠️  HASIL: LULUS DENGAN CATATAN (Ada issue BLOCKER/CRITICAL/MAJOR)"
else
  echo "✅ HASIL: LULUS"
fi