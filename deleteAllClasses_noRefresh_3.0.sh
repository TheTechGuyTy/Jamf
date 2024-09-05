#!/bin/bash
####################################################################################################
#
# THIS SCRIPT IS NOT AN OFFICIAL PRODUCT OF JAMF
# AS SUCH IT IS PROVIDED WITHOUT WARRANTY OR SUPPORT
#
# BY USING THIS SCRIPT, YOU AGREE THAT JAMF
# IS UNDER NO OBLIGATION TO SUPPORT, DEBUG, OR OTHERWISE
# MAINTAIN THIS SCRIPT
#
####################################################################################################
#
# DESCRIPTION
# This is a self descrtuct script that will delete all classes in Jamf Pro.
# Requires a user that has READ and DELETE privys for Classes.
# The noRefesh version goes through 100 at a time before forcing a class refresh with Jamf.
#		This allows the script to run much faster than past scripts.
# Log is stored at /tmp/classes_deleted.txt
# Jul 22, 2024 - version 3.0
# 		updated to accomidate a change that was made to curl
#		added an extra step at the end to create a class and delete it. This forces the class refresh.
#
####################################################################################################

# Variable declarations
bearerToken=""
tokenExpirationEpoch="0"
count=0

# Set the Jamf Pro URL here if you want it hardcoded.
jamfpro_url=""

# Set the username here if you want it hardcoded.
jamfpro_user=""

# Set the password here if you want it hardcoded.
jamfpro_password=""

# Function to gather and format bearer token
getBearerToken() {
	response=$(/usr/bin/curl -k -k -s -u "$jamfpro_user":"$jamfpro_password" "$jamfpro_url"/api/v1/auth/token -X POST)
	bearerToken=$(echo "$response" | plutil -extract token raw -)
	tokenExpiration=$(echo "$response" | plutil -extract expires raw - | awk -F . '{print $1}')
	tokenExpirationEpoch=$(date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s")
	echo "New bearer token generated."
	echo "Token valid until the following date/time UTC: " "$tokenExpiration"
}

# Function to check token expiration
checkTokenExpiration() {
	nowEpochUTC=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
	if [[ tokenExpirationEpoch -lt nowEpochUTC ]]
	then
		echo "No valid token available, getting new token"
		getBearerToken
	fi
}

# Funtion to invalidate token
invalidateToken() {
	responseCode=$(/usr/bin/curl -k -w "%{http_code}" -H "Authorization: Bearer ${bearerToken}" $jamfpro_url/api/v1/auth/invalidate-token -X POST -s -o /dev/null)
	if [[ ${responseCode} == 204 ]]
	then
		echo "Bearer token successfully invalidated"
		bearerToken=""
		tokenExpirationEpoch="0"
	elif [[ ${responseCode} == 401 ]]
	then
		echo "Bearer token already invalid"
	else
		echo "An unknown error occurred invalidating the bearer token"
	fi
}

# Dispaly warning and confrim user would like to continue
echo "#####################"
echo "###!!! WARNING !!!###"
echo "#####################"
echo "This is a self destruct script that will delete all classes."
echo "There is no undo button."
while true; do
	read -p "Are you sure you want to continue? [ y | n ]  " answer
	
	case $answer in
		[Yy]* ) break;;
		[Nn]* ) exit;;
		* ) echo "Please answer y | n";;
	esac
done

# If the Jamf Pro URL, the account username and/or the account password have not been provided,
# the below will prompt the user to enter the necessary information.

if [[ -z "$jamfpro_url" ]]; then
	read -p "Please enter your Jamf Pro server URL : " jamfpro_url
fi

if [[ -z "$jamfpro_user" ]]; then
	read -p "Please enter your Jamf Pro user account : " jamfpro_user
fi

if [[ -z "$jamfpro_password" ]]; then
	read -p "Please enter the password for the $jamfpro_user account: " -s jamfpro_password
fi

# Remove the trailing slash from the Jamf Pro URL if needed.
jamfpro_url=${jamfpro_url%%/}

echo
echo "Credentials received"
echo

# Genrating bearer token
echo "Generating bearer token for server authentication..."
getBearerToken

echo
echo "Deleting all classes now!"

# create array with all class IDs
classID=$(/usr/bin/curl -k --silent --header "Authorization: Bearer ${bearerToken}" --header "accept: text/xml" ${jamfpro_url}/JSSResource/classes | xmllint --format - | awk -F '[<>]' '/<id>/{print $3}')
# starting loop to delete all classes
for class in $classID;do
	# sleep to prevent server overload (commented out for testing)
	# sleep 1
	# log delete attmpt and report to user
	echo
	echo "$(date) - Deleting class ID $class" >> /tmp/classes_deleted.txt
	echo "Deleting class ID $class"
	# checking bearer token expiration
	
	# delete class via API
	if [[ "$count" -lt "100" ]]; then
		checkTokenExpiration
		/usr/bin/curl -k --silent --header "Authorization: Bearer ${bearerToken}" ${jamfpro_url}/JSSResource/classes/id/$class/action/deleteNoRefresh --request DELETE
		((count++))
		echo
	else
		checkTokenExpiration
		/usr/bin/curl -k --silent --header "Authorization: Bearer ${bearerToken}" ${jamfpro_url}/JSSResource/classes/id/$class --request DELETE
		count=0
		echo
	fi
done

#create class for refresh
XML='<class><name>Temp1234</name><description>Temp</description></class>'
echo
echo "Creating Temp1234 class to force the class refresh in Jamf Pro"
echo
checkTokenExpiration
newClass=$(curl --silent --header "Authorization: Bearer ${bearerToken}" --header "Content-type: text/xml" $jamfpro_url/JSSResource/classes/id/1 -X POST -d "$XML" )
newClassID=$(echo "$newClass" | xmllint --format - | awk -F '[<>]' '/<id>/{print $3}')

echo
echo "30 second pause to confirm tenant sync"
echo
sleep 30

# delete new class via API
echo
echo "Deleting Temp1234 class."
echo
checkTokenExpiration
/usr/bin/curl --silent --header "Authorization: Bearer ${bearerToken}" ${jamfpro_url}/JSSResource/classes/id/$newClassID --request DELETE

echo
echo "All classes have been deleted."
echo

# Invalidate bearer token (keep this at the end of the script)
echo "Invalidating bearer token..."
invalidateToken

exit