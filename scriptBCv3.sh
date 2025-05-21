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

CLEAN_GIT_URL="${GIT_URL%.git}"
GIT_URL_WITH_AUTH=$(echo "$GIT_URL" | sed -E "s#https://#https://${GIT_USERNAME}:${GIT_PASSWORD}@#")

mkdir -p "$NAMA_TIKET" && cd "$NAMA_TIKET"

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
  mvn clean install
else
  echo "[*] Tidak ditemukan pom.xml"
fi

# ==========================================
# Step 2: SonarQube Scan
# ==========================================
SONAR_URL="http://10.102.244.26:9000"
PROJECT_KEY="$NAMA_TIKET"
TOKEN="919c23b5c5be86d584217490931dbc1576a83ab8"

echo "[*] Menjalankan Sonar Scanner..."
if [ -f "pom.xml" ]; then
  sonar-scanner -Dsonar.projectKey=$PROJECT_KEY -Dsonar.sources=. -Dsonar.java.binaries=. -Dsonar.host.url=$SONAR_URL -Dsonar.login=$TOKEN
else
  sonar-scanner -Dsonar.projectKey=$PROJECT_KEY -Dsonar.sources=. -Dsonar.host.url=$SONAR_URL -Dsonar.login=$TOKEN
fi

# ==========================================
# Step 3: Fetch and Parse JSON (Without jq)
# ==========================================
sleep 15
HOTSPOT_JSON=$(curl -s -u "$TOKEN:" "$SONAR_URL/api/hotspots/search?projectKey=$PROJECT_KEY")
ISSUE_JSON=$(curl -s -u "$TOKEN:" "$SONAR_URL/api/issues/search?componentKeys=$PROJECT_KEY")

declare -a high_hotspots
declare -a medium_hotspots

while IFS= read -r line; do
  if [[ $line =~ \"securityCategory\":\"([^\"]+)\" ]]; then
    current_cat="${BASH_REMATCH[1]}"
  fi
  if [[ $line =~ \"vulnerabilityProbability\":\"HIGH\" ]]; then
    high_hotspots+=("$current_cat")
  elif [[ $line =~ \"vulnerabilityProbability\":\"MEDIUM\" ]]; then
    medium_hotspots+=("$current_cat")
  fi
done <<< "$(echo "$HOTSPOT_JSON" | tr ',' '\n')"

# ==========================================
# Parse Issue Severity and Message
# ==========================================
declare -A issue_array
declare -A issue_counts=(["BLOCKER"]=0 ["CRITICAL"]=0 ["MAJOR"]=0)

while read -r line; do
  if [[ "$line" =~ \"message\":\"([^\"]+)\" ]]; then
    current_message="${BASH_REMATCH[1]}"
  fi
  if [[ "$line" =~ \"severity\":\"([A-Z]+)\" ]]; then
    severity="${BASH_REMATCH[1]}"
    if [[ "$severity" == "HIGH" || "$severity" == "MEDIUM" ]]; then
      issue_array["$current_message"]="$severity"
    fi
    [[ -n "${issue_counts[$severity]}" ]] && ((issue_counts[$severity]++))
  fi
done <<< "$(echo "$ISSUE_JSON" | tr ',' '\n')"

# ==========================================
# Ringkasan
# ==========================================
echo "=== Daftar Issue MEDIUM / HIGH ==="
for key in "${!issue_array[@]}"; do
  echo "$key : ${issue_array[$key]}"
done

echo ""
echo "============================="
echo "🔎 Ringkasan Hasil Analisis:"
echo "HIGH Security Hotspots   : ${#high_hotspots[@]}"
echo "MEDIUM Security Hotspots : ${#medium_hotspots[@]}"
echo "BLOCKER Issues           : ${issue_counts[BLOCKER]}"
echo "CRITICAL Issues          : ${issue_counts[CRITICAL]}"
echo "MAJOR Issues             : ${issue_counts[MAJOR]}"
echo "============================="
echo ""
echo "URL gitlab : $CLEAN_GIT_URL"
echo "branch: $BRANCH"
echo ""

# ==========================================
# Final Decision Message
# ==========================================
url_view="$SONAR_URL/project/issues?id=$NAMA_TIKET&resolved=false"

if [ "${#high_hotspots[@]}" -gt 0 ] || [ "${#medium_hotspots[@]}" -gt 0 ]; then
  msg="Hasil uji kerentanan source code tidak lulus"
  if [ "${#high_hotspots[@]}" -gt 0 ]; then
    unique_high=($(printf "%s\n" "${high_hotspots[@]}" | sort -u))
    msg+=" terdapat $(IFS=, ; echo "${unique_high[*]}") yang HIGH"
  fi
  if [ "${#medium_hotspots[@]}" -gt 0 ]; then
    unique_medium=($(printf "%s\n" "${medium_hotspots[@]}" | sort -u))
    if [ "${#high_hotspots[@]}" -gt 0 ]; then msg+=" dan"; fi
    msg+=" $(IFS=, ; echo "${unique_medium[*]}") yang MEDIUM"
  fi

  notes=()
  [[ "${issue_counts[BLOCKER]}" -gt 0 ]] && notes+=("BLOCKER")
  [[ "${issue_counts[CRITICAL]}" -gt 0 ]] && notes+=("CRITICAL")
  [[ "${issue_counts[MAJOR]}" -gt 0 ]] && notes+=("MAJOR")
  if [ "${#notes[@]}" -gt 0 ]; then
    msg+=" dengan catatan issue ${notes[*]}"
  fi

  msg+=", hasil dapat dilihat pada $url_view"
  echo "❌ HASIL: $msg"
elif [[ "${issue_counts[BLOCKER]}" -gt 0 || "${issue_counts[CRITICAL]}" -gt 0 || "${issue_counts[MAJOR]}" -gt 0 ]]; then
  notes=()
  [[ "${issue_counts[BLOCKER]}" -gt 0 ]] && notes+=("BLOCKER")
  [[ "${issue_counts[CRITICAL]}" -gt 0 ]] && notes+=("CRITICAL")
  [[ "${issue_counts[MAJOR]}" -gt 0 ]] && notes+=("MAJOR")
  echo "⚠️ HASIL: Hasil uji kerentanan source code lulus dengan catatan issue ${notes[*]}, hasil dapat dilihat pada $url_view"
else
  echo "✅ HASIL: Hasil uji kerentanan source code lulus sepenuhnya, hasil dapat dilihat pada $url_view"
fi