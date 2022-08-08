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
# Requires a user that has READ and DELETE privys for Classes
#
####################################################################################################

# Variable declarations
bearerToken=""
tokenExpirationEpoch="0"

# Set the Jamf Pro URL here if you want it hardcoded.
jamfpro_url=""

# Set the username here if you want it hardcoded.
jamfpro_user=""

# Set the password here if you want it hardcoded.
jamfpro_password=""

# Function to gather and format bearer token
getBearerToken() {
	response=$(/usr/bin/curl -s -u "$jamfpro_user":"$jamfpro_password" "$jamfpro_url"/api/v1/auth/token -X POST)
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
	responseCode=$(/usr/bin/curl -w "%{http_code}" -H "Authorization: Bearer ${bearerToken}" $jamfpro_url/api/v1/auth/invalidate-token -X POST -s -o /dev/null)
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
echo "Please ensure you have a database backup."
echo "There is no undo button other than restoring to a backup from when the classes were in existence."
read -p "Are you sure you want to continue? [ y | n ]  " answer
if [[ $answer != 'y' ]]; then
	echo "Exiting script!"
	exit 1
else
	echo
fi

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
classID=$(/usr/bin/curl --silent --header "Authorization: Bearer ${bearerToken}" --header "accept: text/xml" --URL ${jamfpro_url}/JSSResource/classes | xmllint --format - | awk -F '[<>]' '/id/{print $3}')

# starting loop to delete all classes
for class in $classID;do
	
	# checking bearer token expiration
	checkTokenExpiration
	
	# delete class via API
	/usr/bin/curl --silent --header "Authorization: Bearer ${bearerToken}" --header "Content-type: text/xml" --URL ${jamfpro_url}/JSSResource/classes/id/$class --request DELETE
	echo
done

echo "All classes have been deleted."
echo

# Invalidate bearer token (keep this at the end of the script)
echo "Invalidating bearer token..."
invalidateToken

exit