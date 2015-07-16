#!/bin/bash

function echoc() {
    printf "\033[0;32m$1\033[0m\n"
}

function exec_command() {
	echoc "> $1"
	$1
}

function append_snapshot() {
	# Add -SNAPSHOT to the end (and make sure we don't accidentally have it twice)
	echo "$(echo "$1" | perl -pe 's/-SNAPSHOT//gi')-SNAPSHOT"
}

function die_with() {
	echoc "$*" >&2
	exit 1
}

function has_command() {
	which "$1" >/dev/null 2>/dev/null || return 1
	return 0
}

function has_xmllint_with_xpath() {
	if [ "$(xmllint 2>&1 | grep xpath | wc -l)" = "0" ] ; then
		return 1
	else
		return 0
	fi
}

function die_unless_xmllint_has_xpath() {
	has_command xmllint || die_with "Missing xmllint command, please install it (from libxml2)"
	
	has_xmllint_with_xpath || die_with "xmllint command is missing the --xpath option, please install the libxml2 version"
}

function die_without_command() {
	while [ -n "$1" ]
	do
		has_command "$1" || die_with "Missing required command: $1"
		shift
	done
}

function rollback_and_die_with() {

	MSG=$3
	echoc "$MSG" >&2

	echoc "Deleting artifacts from Archiva in case they were deployed"
	exec_command "mvn  lt.omnitel.maven.plugins:archiva-plugin:0.0.1-SNAPSHOT:deleteArtifacts -DversionToDelete=$RELEASE_VERSION"

	echoc "Resetting release commit to return you to the same working state as before attempting a deploy"

	if ! [ -z "$RELEASE_BRANCH" ] && [ $(git branch --list "${RELEASE_BRANCH}" | wc -l) != "0" ] ; then
		exec_command "git branch -D $RELEASE_BRANCH" || echoc "Could not delete branch"
	fi

	if ! [ -z "$VCS_RELEASE_TAG" ] && [ $(git tag -l "${VCS_RELEASE_TAG}" | wc -l) != "0" ] ; then
		exec_command "git tag -d $VCS_RELEASE_TAG" || echoc "Could not delete tag"
	fi
	exec_command "git reset --hard $HEAD_BEFORE_RELEASE" || echoc "Git reset command failed!"
	exit 1
}

function usage() {
	echoc "Maven git release script v1.0 (c) 2014 Peter Wright"
	echoc ""
	echoc "Usage:"
	echoc "  $0 [-a | [ -r RELEASE_VERSION ] [ -n NEXT_DEV_VERSION ] ]  [ -c ASSUMED_POM_VERSION ] [ -s ]"
	echoc "Updates release version, then builds and commits it"
	echoc ""
	echoc "  -a    Shorthand for -a auto -n auto"
	echoc "  -r    Sets the release version number to use ('auto' to use the version in pom.xml)"
	echoc "  -n    Sets the next development version number to use (or 'auto' to increment release version)"
	echoc "  -mr   Sets the version in release branch"
	echoc "  -c    Assume this as pom.xml version without inspecting it with xmllint"
	echoc ""
	echoc "  -h    For this message"
	echoc ""
}

###############################
# HANDLE COMMAND-LINE OPTIONS #
###############################

while getopts "ahr:n:c:" o; do
	case "${o}" in
		a)
			RELEASE_VERSION="auto"
			NEXT_VERSION="auto"
			NEXT_VERSION_RELEASE_BRANCH="auto"
			;;
		r)
			RELEASE_VERSION="${OPTARG}"
			;;
		n)
			NEXT_VERSION="${OPTARG}"
			;;
		c)
			CURRENT_VERSION="${OPTARG}"
			;;
		mr)
		    NEXT_VERSION_RELEASE_BRANCH="${OPTARG}"
			;;
		h)
			usage
			exit 0
			;;
		*)
			usage
			die_with "Unrecognised option ${o}"
			;;
	esac
done
shift $((OPTIND-1))

###############################################
# MAKE SURE SCRIPT DEPENDENCIES ARE INSTALLED #
###############################################

die_without_command git perl wc

if [ -z "$MVN" ] ; then
	die_without_command mvn
	MVN=mvn
else
	die_without_command $MVN
fi

echoc "Using maven command: $MVN"


#########################################
# BAIL IF GIT STATE INCORRECT #
#########################################

# If there are any uncommitted changes we must abort immediately
if [ $(git status -s | wc -l) != "0" ] ; then
	git status -s
	die_with "There are uncommitted changes, please commit or stash them to continue with the release:"
else
	echoc "Good, no uncommitted changes found"
fi

#################################################################
# FIGURE OUT RELEASE VERSION NUMBER AND NEXT DEV VERSION NUMBER #
#################################################################

if [ -z "$CURRENT_VERSION" ] ; then
	# Extract the current version (requires xmlllint with xpath suport)
	die_unless_xmllint_has_xpath
	CURRENT_VERSION=$(xmllint --xpath "/*[local-name() = 'project']/*[local-name() = 'version']/text()" pom.xml)
fi

echoc "Current pom.xml version: $CURRENT_VERSION"
echoc ""

# Prompt for release version (or compute it automatically if requested)
RELEASE_VERSION_DEFAULT=$(echo "$CURRENT_VERSION" | perl -pe 's/-SNAPSHOT//')
if [ -z "$RELEASE_VERSION" ] ; then
	read -p "Version to release [${RELEASE_VERSION_DEFAULT}]" RELEASE_VERSION
		
	if [ -z "$RELEASE_VERSION" ] ; then
		RELEASE_VERSION=$RELEASE_VERSION_DEFAULT
	fi
elif [ "$RELEASE_VERSION" = "auto" ] ; then
	RELEASE_VERSION=$RELEASE_VERSION_DEFAULT
fi

if [ "$RELEASE_VERSION" = "$CURRENT_VERSION" ] ; then
	die_with "Release version requested is exactly the same as the current pom.xml version (${CURRENT_VERSION})! Is the version in pom.xml definitely a -SNAPSHOT version?"
fi


# Prompt for next version (or compute it automatically if requested)
NEXT_VERSION_DEFAULT=$(echo "$RELEASE_VERSION" | perl -pe 's{^(([0-9]\.)+)?([0-9]+)(\.[0-9]+)$}{$1 . ($3 + 1) . $4}e')
if [ -z "$NEXT_VERSION" ] ; then
	read -p "Next snapshot version [${NEXT_VERSION_DEFAULT}]" NEXT_VERSION
	
	if [ -z "$NEXT_VERSION" ] ; then
		NEXT_VERSION=$NEXT_VERSION_DEFAULT
	fi
elif [ "$NEXT_VERSION" = "auto" ] ; then
	NEXT_VERSION=$NEXT_VERSION_DEFAULT
fi

# Add -SNAPSHOT to the end (and make sure we don't accidentally have it twice)
NEXT_VERSION=$(append_snapshot $NEXT_VERSION)

if [ "$NEXT_VERSION" = "${RELEASE_VERSION}-SNAPSHOT" ] ; then
	die_with "Release version and next version are the same version!"
fi

#Promot for next version in release branch
NEXT_VERSION_RELEASE_BRANCH_DEFAULT=$(echo "$RELEASE_VERSION" | perl -pe 's{^(([0-9]\.)+)?([0-9]+)$}{$1 . ($3 + 1)}e')
if [ -z "$NEXT_VERSION_RELEASE_BRANCH" ] ; then
	read -p "Next snapshot version in release branch [${NEXT_VERSION_RELEASE_BRANCH_DEFAULT}]" $NEXT_VERSION_RELEASE_BRANCH

	if [ -z "$NEXT_VERSION_RELEASE_BRANCH" ] ; then
		NEXT_VERSION_RELEASE_BRANCH=$NEXT_VERSION_RELEASE_BRANCH_DEFAULT
	fi
elif [ "$NEXT_VERSION_RELEASE_BRANCH" = "auto" ] ; then
	NEXT_VERSION_RELEASE_BRANCH=$NEXT_VERSION_RELEASE_BRANCH_DEFAULT
fi

NEXT_VERSION_RELEASE_BRANCH=$(append_snapshot $NEXT_VERSION_RELEASE_BRANCH)
if [ "NEXT_VERSION_RELEASE_BRANCH" = "${RELEASE_VERSION}-SNAPSHOT" ] ; then
	die_with "Release version in branch and next version are the same version!"
fi

echoc ""
echoc "Using $RELEASE_VERSION for release"
echoc "Using $NEXT_VERSION for next development version"
echoc "Using $NEXT_VERSION_RELEASE_BRANCH for next development version in branch"

STARTING_BRANCH=$(git symbolic-ref --short -q HEAD)
HEAD_BEFORE_RELEASE=$(git rev-parse HEAD)
VCS_RELEASE_TAG="${RELEASE_VERSION}"
RELEASE_BRANCH="release-$RELEASE_VERSION"

#############################
# START THE RELEASE PROCESS #
#############################


# check that tag and release branch doesn't exist
if [ $(git tag -l "${VCS_RELEASE_TAG}" | wc -l) != "0" ] ; then
	die_with "A tag already exists ${VCS_RELEASE_TAG} for the release version ${RELEASE_VERSION}"
fi
if [ $(git branch --list "${RELEASE_BRANCH}" | wc -l) != "0" ] ; then
	die_with "A release branch already exists ${RELEASE_BRANCH} for the release version ${RELEASE_VERSION}"
fi

# Update the pom.xml versions
$MVN versions:set -DgenerateBackupPoms=false -DnewVersion=$RELEASE_VERSION || die_with "Failed to set release version on pom.xml files"

# Commit the updated pom.xml files
git commit -a -m "Release version ${RELEASE_VERSION}" || rollback_and_die_with "Failed to commit updated pom.xml versions for release!"

echoc ""
echoc " Starting build and deploy"
echoc ""


# build and deploy the release
$MVN -DperformRelease=true clean deploy || rollback_and_die_with "Build/Deploy failure. Release failed."

# tag the release (N.B. should this be before perform the release?)
git tag "${VCS_RELEASE_TAG}" || rollback_and_die_with "Failed to create tag ${RELEASE_VERSION}! Release has been deployed, however"

#########################
# CREATE RELEASE BRANCH #
#########################

git checkout -b $RELEASE_BRANCH || rollback_and_die_with "Can not create realease branch $RELEASE_BRANCH"

mvn versions:set -f pom.xml -DnewVersion=$NEXT_VERSION_RELEASE_BRANCH || rollback_and_die_with "Can't update pom version to $NEXT_VERSION_RELEASE_BRANCH"
mvn versions:commit -f pom.xml || rollback_and_die_with "Can't commit $NEXT_VERSION_RELEASE_BRANCH pom.xml"

git commit -a -m "Prepare release branch for bug-fix development. Bumping version to $NEXT_VERSION_RELEASE_BRANCH."
git checkout $STARTING_BRANCH


######################################
# START THE NEXT DEVELOPMENT PROCESS #
######################################

$MVN versions:set -DgenerateBackupPoms=false "-DnewVersion=${NEXT_VERSION}" || rollback_and_die_with "Failed to set next dev version on pom.xml files, please do this manually"

git commit -a -m "Start next development version ${NEXT_VERSION}" || rollback_and_die_with "Failed to commit updated pom.xml versions for next dev version! Please do this manually"

git checkout $RELEASE_BRANCH
git push || die_with "Failed to push commits from $RELEASE_BRANCH. Please do this manually"
git checkout $STARTING_BRANCH
git push || die_with "Failed to push commits. Please do this manually"
git push --tags || die_with "Failed to push tags. Please do this manually"
