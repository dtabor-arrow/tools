#!/usr/local/bin/bash

# Lists all Perspectives and then lists all groups in the various Perspectives.
# Outputs Perspectives.csv (the list) and $groupName.csv which has the groups in each Perspective.

#TO DO: Make a Python version of this

read -p 'Enter your CloudHealth API key: ' API_KEY

# List all Perspectives
echo "Generating Perspective list"

curl -s "https://chapi.cloudhealthtech.com/v1/perspective_schemas?api_key=$API_KEY" | \
jq -r 'to_entries | map({id: .key} + .value)[] | select(.active == true) | [.id, .name] | @csv' | tr -d '"' | sort -k2 -t \, >Perspectives.csv

echo Count of Perspectives: $(wc -l <Perspectives.csv)
echo ""

while read -r i
	do

	# for each Perspective in the list, get the number and name

	pNUMBER=$(echo "$i" | cut -d "," -f1)
	pNAME=$(echo "$i" | cut -d "," -f2)

	# for each Perspective, get the group number and name

	curl -s -H "Accept: application/json" "https://chapi.cloudhealthtech.com/v1/perspective_schemas/$pNUMBER?api_key=$API_KEY" | \
	jq -r '.schema.constants[].list[] | [.ref_id, .name] | @csv' | tr -d '"' | sort -k2 -t \, >"$pNAME".csv

	echo $pNAME:   $(wc -l <"$pNAME".csv) groups

done < Perspectives.csv
