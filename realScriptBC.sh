#!/bin/bash

# Hardcoded Git username/email
GIT_USERNAME="syarief.hidayatulloh%40compnet.co.id"

# Minta password dari user (disembunyikan saat input)
read -s -p "Masukkan password untuk Git: " GIT_PASSWORD
echo ""

# Validasi argumen
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <nama_tiket> <git_url> <branch>"
  echo "Contoh: $0 TICKET-001 https://github.com/user/repo.git main"
  exit 1
fi

NAMA_TIKET=$1
GIT_URL=$2
BRANCH=$3

# Format ulang URL Git dengan username dan password
GIT_URL_WITH_AUTH=$(echo "$GIT_URL" | sed -E "s#https://#https://${GIT_USERNAME}:${GIT_PASSWORD}@#")

# Buat folder dan masuk ke dalamnya
mkdir -p "$NAMA_TIKET" && cd "$NAMA_TIKET" || exit 1

# Clone repositori
git clone -b "$BRANCH" "$GIT_URL_WITH_AUTH" . || {
  echo "Gagal clone repo dari $GIT_URL branch $BRANCH"
  exit 1
}

# Jalankan Maven jika ada pom.xml
if [ -f "pom.xml" ]; then
  echo "Menjalankan mvn clean install..."
  mvn clean install
else
  echo "Tidak ada pom.xml, skip build Maven."
fi