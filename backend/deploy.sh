#!/bin/bash

#
# Upload files to the server...
#

remote_user="debian"
remote_host="rund"
remote_directory="/home/debian/rund"

files=(
"backend/Dockerfile"
"backend/app.py"
"backend/compose.yaml"
"backend/main.py"
"backend/requirements.txt"
"backend/db.py"
"backend/utm.py"
"backend/places.py"
"backend/create-db-gapi.sh"
"backend/create-db-oapi.sh"
)

# Convert the array of files to a space-separated string
files_to_send="${files[@]}"

# Send all the files at once via SCP
echo "[+] Sending files to $remote_user@$remote_host:$remote_directory..."
scp $files_to_send "$remote_user@$remote_host:$remote_directory"

# Check if the SCP command was successful
if [ $? -eq 0 ]; then
    echo "[+] Files sent successfully."
else
    echo "[+] Failed to send files."
fi

echo "[+] Updating the container..."
ssh $remote_user@$remote_host 'cd rund && docker compose down && docker build -t rund . && docker compose up -d'

# Check if the docker commands was successful
if [ $? -eq 0 ]; then
    echo "[+] Container successfully updated."
else
    echo "[+] Failed to update the container."
fi
