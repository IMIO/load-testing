#!/usr/bin/env bash
set -e -o pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/concurrent.lib.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.lib.sh"

read -p "Enter website: (e.g. www.theux.be): " WEBSITE
WEBSITE=${WEBSITE:-"www.theux.be"}
echo ''

read -p "Enter start date: (e.g 2016-07-19 16:15:36): " START_DATE
START_DATE=${START_DATE:-"2016-07-19 16:15:36"}
echo ''

read -p "Enter end date: (e.g 2016-07-19 16:30:36): " END_DATE
END_DATE=${END_DATE:-"2016-07-19 16:30:36"}
echo ''

echo $WEBSITE $START_DATE $END_DATE
fetch_urls $WEBSITE "$START_DATE" "$END_DATE" > test1/$WEBSITE.csv
#echo "Created test1/$WEBSITE.csv"
