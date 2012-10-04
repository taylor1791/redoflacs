#!/bin/bash

#------------------------------------------------------------
# Re-compress, Verify, Test, Re-tag, and Clean Up FLAC Files
#                     Version 0.14.2
#                       sirjaren
#------------------------------------------------------------

#-----------------------------------------------------------------
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#-----------------------------------------------------------------
# You can follow development of this script on Github at:
# https://github.com/sirjaren/redoflacs
#
# Please submit requests/changes/patches and/or comments
#-----------------------------------------------------------------

tags=(
########################
#  USER CONFIGURATION  #
########################
# List the tags to be kept in each FLAC file
# The default is listed below.
# Be sure not to delete the parenthesis ")" below
# or put wanted tags below it! Another common tag
# not added by default is ALBUMARTIST.  Uncomment
# ALBUMARTIST below to allow script to keep this
# tag.

TITLE
ARTIST
#ALBUMARTIST
ALBUM
DISCNUMBER
DATE
TRACKNUMBER
TRACKTOTAL
GENRE

# The COMPRESSION tag is a custom tag to allow
# the script to determine which level of compression
# the FLAC file(s) has/have been compressed at.
COMPRESSION

# The RELEASETYPE tag is a custom tag the author
# of this script uses to catalogue what kind of
# release the album is (ie, Full Length, EP,
# Demo, etc.).
RELEASETYPE

# The SOURCE tag is a custom tag the author of
# this script uses to catalogue which source the
# album has derived from (ie, CD, Vinyl,
# Digital, etc.).
SOURCE

# The MASTERING tag is a custom tag the author of
# this script uses to catalogue how the album has
# been mastered (ie, Lossless, or Lossy).
MASTERING

# The REPLAYGAIN tags below, are added by the
# --replaygain, -g argument.  If you want to
# keep the replaygain tags, make sure you leave
# these here.
REPLAYGAIN_REFERENCE_LOUDNESS
REPLAYGAIN_TRACK_GAIN
REPLAYGAIN_TRACK_PEAK
REPLAYGAIN_ALBUM_GAIN
REPLAYGAIN_ALBUM_PEAK

) # <- DO NOT DELETE PARENTHESIS!

# Set whether to remove embedded artwork within FLAC
# files.  By default, this script will remove any
# artwork it can find, whether it's in the legacy
# COVERART tag or METADATA_BLOCK_PICTURE.  Legal
# values are:
#    "true"  (Remove Artwork)
#    "false" (Keep Artwork)
REMOVE_ARTWORK="true"

# Set the type of COMPRESSION to compress the
# FLAC files.  Numbers range from 1-8, with 1 being
# the lowest compression and 8 being the highest
# compression.  The default is 8.
COMPRESSION_LEVEL=8

# Set the number of threads/cores to use
# when running this script.  The default
# number of threads/cores used is 2
CORES=2

# Set the where you want the error logs to
# be placed. By default, they are placed in
# the user's HOME directory.
ERROR_LOG="${HOME}"

# Set where the auCDtect command is located.
# By default, the script will look in $PATH
# An example of changing where to find auCDtect
# is below:
# AUCDTECT_COMMAND="/${HOME}/auCDtect"
AUCDTECT_COMMAND="$(command -v auCDtect)"

# Set where the created spectrogram files should
# be placed. By default, the spectrogram PNG files
# will be placed in the same directory as the tested
# FLAC files. Each PNG will have the same name as
# the tested FLAC file but with the extension ".png"
#
# The special value, "default" does the default
# action.  Other values are interpreted as a
# directory. An example of a user-defined location:
# SPECTROGRAM_LOCATION="${HOME}/Spectrogram_Images"
#
# See "--help" or "-h" for more information.
SPECTROGRAM_LOCATION="default"
##########################
#  END OF CONFIGURATION  #
##########################

######################
#  STATIC VARIABLES  #
######################
# Version
VERSION="0.14.2"

# Export REMOVE_ARTWORK to allow subshell access
export REMOVE_ARTWORK

# Export COMPRESSION_LEVEL to allow subshell access
export COMPRESSION_LEVEL

# Export auCDtect command to allow subshell access
export AUCDTECT_COMMAND

# Export SPECTROGRAM_LOCATION to allow subshell access
export SPECTROGRAM_LOCATION

# Export the tag array using some trickery (BASH doesn't
# support exporting arrays natively)
export EXPORT_TAG="$(printf "%s\n" "${tags[@]}")"

# Colors on by default
# Export to allow subshell access
export BOLD_GREEN="\033[1;32m"
export BOLD_RED="\033[1;31m"
export BOLD_BLUE="\033[1;34m"
export CYAN="\033[0;36m"
export NORMAL="\033[0m"
export YELLOW="\033[0;33m"

# Log files with timestamp
# Export to allow subshell access
export VERIFY_ERRORS="${ERROR_LOG}/FLAC_Verify_Errors $(date "+[%Y-%m-%d %R]")"
export TEST_ERRORS="${ERROR_LOG}/FLAC_Test_Errors $(date "+[%Y-%m-%d %R]")"
export MD5_ERRORS="${ERROR_LOG}/MD5_Signature_Errors $(date "+[%Y-%m-%d %R]")"
export METADATA_ERRORS="${ERROR_LOG}/FLAC_Metadata_Errors $(date "+[%Y-%m-%d %R]")"
export REPLAY_TEST_ERRORS="${ERROR_LOG}/ReplayGain_Test_Errors $(date "+[%Y-%m-%d %R]")"
export REPLAY_ADD_ERRORS="${ERROR_LOG}/ReplayGain_Add_Errors $(date "+[%Y-%m-%d %R]")"
export AUCDTECT_ERRORS="${ERROR_LOG}/auCDtect_Errors $(date "+[%Y-%m-%d %R]")"
export PRUNE_ERRORS="${ERROR_LOG}/FLAC_Prune_Errors $(date "+[%Y-%m-%d %R]")"

# Set arguments to null
# If enabled they will be changed to true
COMPRESS=""
TEST=""
AUCDTECT=""
MD5CHECK=""
REPLAYGAIN=""
REDO=""
PRUNE=""

###################################
#  INFORMATION PRINTED TO STDOUT  # 
###################################
# Displaying currently running tasks
function title_compress_flac {
	printf "%s${BOLD_GREEN}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\n" \
	" " "*" " Compressing FLAC files with level ${COMPRESSION_LEVEL} compression and verifying output :: " "[${CORES} Thread(s)]"
}

function title_compress_notest_flac {
	printf "%s${BOLD_GREEN}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\n" \
	" " "*" " Compressing FLAC files with level ${COMPRESSION_LEVEL} compression :: " "[${CORES} Thread(s)]"
}

function title_test_replaygain {
	printf "%s${BOLD_GREEN}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\n" \
	" " "*" " Verifying FLAC Files can have ReplayGain Tags added :: " "[${CORES} Thread(s)]"
}

# This is NOT multithreaded (1 thread only)
# This is intentional
function title_add_replaygain {
	printf "%s${BOLD_GREEN}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\n" \
	" " "*" " Applying ReplayGain values by album directory :: " "[1 Thread(s)]"
}

function title_analyze_tags {
	printf "%s${BOLD_GREEN}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\n" \
	" " "*" " Analyzing FLAC Tags :: " "[${CORES} Thread(s)]"
}

function title_setting_tags {
	printf "%s${BOLD_GREEN}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\n" \
	" " "*" " Setting new FLAC Tags :: " "[${CORES} Thread(s)]"
}

function title_testing_flac {
	printf "%s${BOLD_GREEN}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\n" \
	" " "*" " Testing the integrity of each FLAC file :: " "[${CORES} Thread(s)]"
}

function title_aucdtect_flac {
	printf "%s${BOLD_GREEN}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\n" \
	" " "*" " Validating FLAC is not lossy sourced :: " "[${CORES} Thread(s)]"
}

function title_md5check_flac {
	printf "%s${BOLD_GREEN}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\n" \
	" " "*" " Verifying the MD5 Signature in each FLAC file :: " "[${CORES} Thread(s)]"
}

function title_prune_flac {
	printf "%s${BOLD_GREEN}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\n" \
	" " "*" " Removing the SEEKTABLE and PADDING block from each FLAC file :: " "[${CORES} Thread(s)]"
}

# Error messages
# Don't display threads as script will quit after diplaying
function no_flacs {
	printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
	" " "*" " There are not any FLAC files to process!"
}

# Information relating to currently running tasks
function print_compressing_flac {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ Compressing FLAC ] (20) minus 3 (leaves a gap and the gives room for the
	# ellipsis (…) and cursor)
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 30))"

	FILENAME="${i##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 20))s${BOLD_BLUE}%s${NORMAL}%s${YELLOW}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${NORMAL}${YELLOW}%s${NORMAL}%s" \
	"" "[" " " "Compressing FLAC" " " "]" "     " "*" " ${FILENAME}"
}
function print_test_replaygain {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ Testing ReplayGain ] (22) minus 3 (leaves a gap and the gives room for the
	# ellipsis (…) and cursor)
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 32))"

	FILENAME="${i##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 22))s${BOLD_BLUE}%s${NORMAL}%s${YELLOW}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${NORMAL}${YELLOW}%s${NORMAL}%s" \
	"" "[" " " "Testing ReplayGain" " " "]" "     " "*" " ${FILENAME}"
}
function print_add_replaygain {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ Adding ReplayGain ] (21) minus ' [Directory]' (12) minus 3 (leaves a gap and the gives room for the
	# ellipsis (…) and cursor)
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 43))"

	FILENAME="${FLAC_LOCATION##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 21))s${BOLD_BLUE}%s${NORMAL}%s${YELLOW}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${NORMAL}${YELLOW}%s${NORMAL}%s${CYAN}%s${NORMAL}" \
	"" "[" " " "Adding ReplayGain" " " "]" "     " "*" " ${FILENAME} " "[Directory]"
}
function print_testing_flac {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ Testing FLAC ] (16) minus 3 (leaves a gap and the gives room for the
	# ellipsis (…) and cursor)
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 26))"

	FILENAME="${i##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi
	
	printf "\r${NORMAL}%$((${COLUMNS} - 16))s${BOLD_BLUE}%s${NORMAL}%s${YELLOW}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${NORMAL}${YELLOW}%s${NORMAL}%s" \
	"" "[" " " "Testing FLAC" " " "]" "     " "*" " ${FILENAME}"
}
function print_failed_flac {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ FAILED ] (10) minus 2 (leaves a gap and the gives room for the ellipsis (…))
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 19))"

	FILENAME="${i##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 10))s${BOLD_BLUE}%s${NORMAL}%s${BOLD_RED}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${YELLOW}%s${NORMAL}%s\n" \
	"" "[" " " "FAILED" " " "]" "     " "*" " ${FILENAME}"
}
function print_failed_replaygain {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ FAILED ] (10) minus 2 (leaves a gap and the gives room for the
	# ellipsis (…) and cursor)
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 19))"

	FILENAME="${FLAC_LOCATION##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 10))s${BOLD_BLUE}%s${NORMAL}%s${BOLD_RED}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${NORMAL}${YELLOW}%s${NORMAL}%s${CYAN}%s${NORMAL}\n" \
	"" "[" " " "FAILED" " " "]" "     " "*" " ${FILENAME} " "[Directory]"
}
function print_checking_md5 {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ Checking MD5 ] (16) minus 3 (leaves a gap and the gives room for the
	# ellipsis (…) and cursor)
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 26))"

	FILENAME="${i##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 16))s${BOLD_BLUE}%s${NORMAL}%s${YELLOW}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${NORMAL}${YELLOW}%s${NORMAL}%s" \
	"" "[" " " "Checking MD5" " " "]" "     " "*" " ${FILENAME}"
}
function print_ok_flac {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ OK ] (6) minus 2 (leaves a gap and the gives room for the ellipsis (…))
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 15))"

	FILENAME="${i##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 6))s${BOLD_BLUE}%s${NORMAL}%s${BOLD_GREEN}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${YELLOW}%s${NORMAL}%s\n" \
	"" "[" " " "OK" " " "]" "     " "*" " ${FILENAME}"
}
function print_ok_replaygain {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ OK ] (6) minus 2 (leaves a gap and the gives room for the
	# ellipsis (…) and cursor)
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 15))"

	FILENAME="${FLAC_LOCATION##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 6))s${BOLD_BLUE}%s${NORMAL}%s${BOLD_GREEN}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${NORMAL}${YELLOW}%s${NORMAL}%s${CYAN}%s${NORMAL}\n" \
	"" "[" " " "OK" " " "]" "     " "*" " ${FILENAME} " "[Directory]"
}
function print_aucdtect_flac {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ Validating FLAC ] (19) minus 3 (leaves a gap and the gives room for the
	# ellipsis (…) and cursor)
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 29))"

	FILENAME="${i##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 19))s${BOLD_BLUE}%s${NORMAL}%s${YELLOW}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${NORMAL}${YELLOW}%s${NORMAL}%s" \
	"" "[" " " "Validating FLAC" " " "]" "     " "*" " ${FILENAME}"
}
function print_aucdtect_issue {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ ISSUE ] (9) minus 2 (leaves a gap and the gives room for the ellipsis (…))
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 18))"

	FILENAME="${i##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 9))s${BOLD_BLUE}%s${NORMAL}%s${YELLOW}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${YELLOW}%s${NORMAL}%s\n" \
	"" "[" " " "ISSUE" " " "]" "     " "*" " ${FILENAME}"
}
function print_aucdtect_spectrogram {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ Creating Spectrogram ] (24) minus 3 (leaves a gap and the gives room for the
	# ellipsis (…) and cursor)
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 34))"

	FILENAME="${i##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 24))s${BOLD_BLUE}%s${NORMAL}%s${YELLOW}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${NORMAL}${YELLOW}%s${NORMAL}%s" \
	"" "[" " " "Creating Spectrogram" " " "]" "     " "*" " ${FILENAME}"
}
function print_aucdtect_skip {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ SKIPPED ] (11) minus 2 (leaves a gap and the gives room for the ellipsis (…))
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 20))"

	FILENAME="${i##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 11))s${BOLD_BLUE}%s${NORMAL}%s${YELLOW}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${YELLOW}%s${NORMAL}%s\n" \
	"" "[" " " "SKIPPED" " " "]" "     " "*" " ${FILENAME}"
}
function print_done_flac {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ DONE ] (8) minus 2 (leaves a gap and the gives room for the ellipsis (…))
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 17))"

	FILENAME="${i##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 8))s${BOLD_BLUE}%s${NORMAL}%s${BOLD_GREEN}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${YELLOW}%s${NORMAL}%s\n" \
	"" "[" " " "DONE" " " "]" "     " "*" " ${FILENAME}"
}
function print_level_same_compression {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ Already At Level 8 ] (22) minus 2 (leaves a gap and the gives room for
	#the ellipsis (…))
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 31))"

	FILENAME="${i##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 22))s${BOLD_BLUE}%s${NORMAL}%s${YELLOW}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${YELLOW}%s${NORMAL}%s\n" \
	"" "[" " " "Already At Level ${COMPRESSION_LEVEL}" " " "]" "     " "*" " ${FILENAME}"
}
function print_analyzing_tags {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ Analyzing Tags ] (18) minus 3 (leaves a gap and the gives room for the
	# ellipsis (…) and cursor)
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 28))"

	FILENAME="${i##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 18))s${BOLD_BLUE}%s${NORMAL}%s${YELLOW}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${NORMAL}${YELLOW}%s${NORMAL}%s" \
	"" "[" " " "Analyzing Tags" " " "]" "     " "*" " ${FILENAME}"
}
function print_setting_tags {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [ Setting Tags ] (16) minus 3 (leaves a gap and the gives room for the
	# ellipsis (…) and cursor)
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 26))"

	FILENAME="${i##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 16))s${BOLD_BLUE}%s${NORMAL}%s${YELLOW}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${NORMAL}${YELLOW}%s${NORMAL}%s" \
	"" "[" " " "Setting Tags" " " "]" "     " "*" " ${FILENAME}"
}
function print_prune_flac {
	# Grab the first line of 'stty -a' output
	# Redirecting '/dev/stderr' to 'stty' allows valid arguments
	read -r COLUMNS < <(stty -a < /dev/stderr)

	# Remove superflous information from 'stty -a'
	# Ends up with number of ${COLUMNS}
	COLUMNS="${COLUMNS/#*columns }"
	COLUMNS="${COLUMNS/%;*}"

	# This is the number of $COLUMNS minus the indent (7) minus length of the printed
	# message, [Pruning Metadata] (20) minus 3 (leaves a gap and the gives room for the
	# ellipsis (…) and cursor)
	MAX_FILENAME_LENGTH="$((${COLUMNS} - 30))"

	FILENAME="${i##*/}"
	FILENAME_LENGTH="${#FILENAME}"

	if [[ "${FILENAME_LENGTH}" -gt "${MAX_FILENAME_LENGTH}" ]] ; then
		FILENAME="${FILENAME::$MAX_FILENAME_LENGTH}…"
	fi

	printf "\r${NORMAL}%$((${COLUMNS} - 20))s${BOLD_BLUE}%s${NORMAL}%s${YELLOW}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\r%s${NORMAL}${YELLOW}%s${NORMAL}%s" \
	"" "[" " " "Pruning Metadata" " " "]" "     " "*" " ${FILENAME}"
}

# Export all the above functions for subshell access
export -f print_compressing_flac
export -f print_test_replaygain
export -f print_add_replaygain
export -f print_testing_flac
export -f print_failed_flac
export -f print_checking_md5
export -f print_ok_flac
export -f print_ok_replaygain
export -f print_aucdtect_flac
export -f print_aucdtect_issue
export -f print_aucdtect_spectrogram
export -f print_aucdtect_skip
export -f print_done_flac
export -f print_level_same_compression
export -f print_analyzing_tags 
export -f print_setting_tags
export -f print_prune_flac

######################################
#  FUNCTIONS TO DO VARIOUS COMMANDS  #
######################################
# General abort script to use BASH's trap command on SIGINT
function normal_abort {
	printf "\n%s${BOLD_GREEN}%s${NORMAL}%s${BOLD_BLUE}%s${NORMAL}\n" \
	" " "*" " Control-C received, exiting script..."
	exit 0
}


# Create a countdown function for the metadata
# to allow user to quit script safely
function countdown_metadata {
	# Creates the listing of tags to be kept
	function tags_countdown {
		# Recreate the tags array so it can be parsed easily
		eval "tags=(${EXPORT_TAG[*]})"
		for i in "${tags[@]}" ; do
			printf "%s\n" "     ${i}"
		done
	}

	# Creates the 10 second countdown
	function countdown_10 {
		COUNT=10
		while [[ ${COUNT} -gt 1 ]] ; do
			printf "${BOLD_RED}%s${NORMAL}%s" "$COUNT" " "
			sleep 1
			((COUNT--))
		done
		# Below is the last second of the countdown
		# Put here for UI refinement (No extra spacing after last second)
		printf "${BOLD_RED}%s${NORMAL}" "1"
		sleep 1
		printf "\n\n"
	}

	# Trap SIGINT (Control-C) to abort cleanly
	trap normal_abort SIGINT

	printf "%s${YELLOW}%s${NORMAL}%s\n" \
	" " "*" " CAUTION! These are the tag fields that will be kept"
	printf "%s${YELLOW}%s${NORMAL}%s\n\n" \
	" " "*" " when re-tagging the selected files:"
	tags_countdown
	printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
	" " "*" " By default, this script will REMOVE embedded coverart"
	printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
	" " "*" " when re-tagging the files (that have the legacy COVERART"
	printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
	" " "*" " tag).  Change the REMOVE_ARTWORK option under USER"
	printf "%s${BOLD_RED}%s${NORMAL}%s\n\n" \
	" " "*" " CONFIGURATION to \"false\" to keep embedded artwork."
	printf "%s${YELLOW}%s${NORMAL}%s\n" \
	" " "*" " Waiting 10 seconds before starting script..."
	printf "%s${YELLOW}%s${NORMAL}%s\n" \
	" " "*" " Ctrl+C (Control-C) to abort..."
	printf "%s${BOLD_GREEN}%s${NORMAL}%s" \
	" " "*" " Starting in: "
	countdown_10
}

################
#  REPLAYGAIN  #
################
# Add ReplayGain to files and make sure each album disc uses the same
# ReplayGain values (multi-disc albums have their own ReplayGain) as well
# as make the tracks have their own ReplayGain values individually.
function replaygain {
	title_test_replaygain

	# Trap SIGINT (Control-C) to abort cleanly
	trap normal_abort SIGINT

	function test_replaygain {
		for i ; do
			print_test_replaygain

			# Check if file is a FLAC file (variable hides output)
			CHECK_FLAC="$(metaflac --show-md5sum "${i}" 2>&1)"

			# If above command return anything other than '0', log output
			if [[ "${?}" -ne "0" ]] ; then
				printf "%s\n%s\n%s\n" \
					   "File:  ${i}" \
					   "Error: The above file does not appear to be a FLAC file" \
					   "------------------------------------------------------------------" \
					   >> "${REPLAY_TEST_ERRORS}"
				# File is not a FLAC file, display failed
				print_failed_flac
			else
				# File is a FLAC file, erase any ReplayGain tags, display ok
				metaflac --remove-replay-gain "${i}"
				print_ok_flac
			fi
		done
	}
	export -f test_replaygain

	# Run the above function with the configured threads (multithreaded)
	find "${DIRECTORY}" -name "*.[Ff][Ll][Aa][Cc]" -print0 | xargs -0 -n 1 -P "${CORES}" bash -c 'test_replaygain "${@}"' --

	if [[ -f "${REPLAY_TEST_ERRORS}" ]] ; then
		printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " There were issues with some of the FLAC files,"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " please check:"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " \"${REPLAY_TEST_ERRORS}\" for details."
		exit 1
	fi

	# The below stuff cannot be done in parallel to prevent race conditions
	# from making the script think some FLAC files have already had
	# ReplayGain tags added to them.  Due to the nature of processing the
	# album tags as a whole, this MUST be done without multithreading.

	title_add_replaygain

	find "${DIRECTORY}" -name "*.[Ff][Ll][Aa][Cc]" -print | while read i ; do
		# Find where the FLAC file is in the DIRECTORY hierarchy
		FLAC_LOCATION="$(printf "%s" "${i%/*}")"

		# Test if DIRECTORY is the current working directory (AKA: ./)
		# as well as check if FLAC_LOCATION is equal to "./"
		if [[ "${DIRECTORY}" == "." && "${FLAC_LOCATION}" = "." ]] ; then
			# We want to be able to display a directory path, so we create
			# the pathname to the FLAC files
			FLAC_LOCATION="${PWD}"
		fi

		# Find the basename directory from FLAC_LOCATION (this is the supposed
		# album name to be printed)
		ALBUM_BASENAME="$(printf "%s" "${FLAC_LOCATION##*/}")"

		# Check if FLAC files have existing ReplayGain tags
		REPLAYGAIN_REFERENCE_LOUDNESS="$(metaflac --show-tag=REPLAYGAIN_REFERENCE_LOUDNESS "${i}")"
		REPLAYGAIN_REFERENCE_LOUDNESS="${REPLAYGAIN_REFERENCE_LOUDNESS#*=}"

		REPLAYGAIN_TRACK_GAIN="$(metaflac --show-tag=REPLAYGAIN_TRACK_GAIN "${i}")"
		REPLAYGAIN_TRACK_GAIN="${REPLAYGAIN_TRACK_GAIN#*=}"

		REPLAYGAIN_TRACK_PEAK="$(metaflac --show-tag=REPLAYGAIN_TRACK_PEAK "${i}")"
		REPLAYGAIN_TRACK_PEAK="${REPLAYGAIN_TRACK_PEAK#*=}"

		REPLAYGAIN_ALBUM_GAIN="$(metaflac --show-tag=REPLAYGAIN_ALBUM_GAIN "${i}")"
		REPLAYGAIN_ALBUM_GAIN="${REPLAYGAIN_ALBUM_GAIN#*=}"

		REPLAYGAIN_ALBUM_PEAK="$(metaflac --show-tag=REPLAYGAIN_ALBUM_PEAK "${i}")"
		REPLAYGAIN_ALBUM_PEAK="${REPLAYGAIN_ALBUM_PEAK#*=}"

		if [[ -n "${REPLAYGAIN_REFERENCE_LOUDNESS}" && -n "${REPLAYGAIN_TRACK_GAIN}" && \
			  -n "${REPLAYGAIN_TRACK_PEAK}" && -n "${REPLAYGAIN_ALBUM_GAIN}" && \
			  -n "${REPLAYGAIN_ALBUM_PEAK}" ]] ; then
			# All ReplayGain tags accounted for, skip this file
			continue
		elif [[ "${REPLAYGAIN_ALBUM_FAILED}" == "${ALBUM_BASENAME} FAILED" ]] ; then
			# This album (directory of FLACS) had at LEAST one FLAC fail, so skip
			# files that are in this album (directory)
			continue
		else
			# Add ReplayGain tags to the files in this directory (which SHOULD include
			# the current working FLAC file [$i])
			print_add_replaygain
			ERROR="$((metaflac --add-replay-gain "${FLAC_LOCATION}"/*.[Ff][Ll][Aa][Cc]) 2>&1)"
			if [[ -n "${ERROR}" ]] ; then
				print_failed_replaygain
				printf "%s\n%s\n%s\n" \
					   "Directory: ${FLAC_LOCATION}" \
					   "Error:     ${ERROR}" \
					   "------------------------------------------------------------------" \
					   >> "${REPLAY_ADD_ERRORS}"
				# Set variable to let script know this album failed and not NOT
				# continue checking the files in this album
				REPLAYGAIN_ALBUM_FAILED="${ALBUM_BASENAME} FAILED"
			else
				print_ok_replaygain
			fi
		fi
	done

	if [[ -f "${REPLAY_ADD_ERRORS}" ]] ; then
		printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " There were issues with some of the FLAC files,"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " please check:"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " \"${REPLAY_ADD_ERRORS}\" for details."
		exit 1
	fi
}

#############################
#  COMPRESS & VERIFY FLACS  #
#############################
# Compress FLAC files and verify output
function compress_flacs {

	# If '-C, --compress-notest' was called, print the
	# correct title
	if [[ "${SKIP_TEST}" == "true" ]] ; then
		title_compress_notest_flac
	else
		title_compress_flac
	fi

	# Abort script and remove temporarily encoded FLAC files (if any)
	# and check for any errors thus far
	function compress_abort {
		printf "\n%s${BOLD_GREEN}%s${NORMAL}%s\n" \
		" " "*" " Control-C received, removing temporary files and exiting script..."
		find "${DIRECTORY}" -name "*.tmp,fl-ac+en\'c" -exec rm "{}" \;
		if [[ -f "${VERIFY_ERRORS}" ]] ; then
			printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " Errors found in some FLAC files, please check:"
			printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " \"${VERIFY_ERRORS}\" for errors"
		fi
		exit 1
	}

	# Trap SIGINT (Control-C) to abort cleanly
	trap compress_abort SIGINT

	function compress_f {
		for i ; do
			# Trap errors into a variable as the output doesn't help
			# for there is a better way to test below using the
			# ERROR variable
			COMPRESSION="$((metaflac --show-tag=COMPRESSION "${i}") 2>&1)"
			COMPRESSION="${COMPRESSION/#[Cc][Oo][Mm][Pp][Rr][Ee][Ss][Ss][Ii][Oo][Nn]=}"
			if [[ "${COMPRESSION}" != "${COMPRESSION_LEVEL}" ]] ; then
				print_compressing_flac
				# This must come after the above command for proper formatting
				ERROR="$((flac -f -${COMPRESSION_LEVEL} -V -s "${i}") 2>&1)"
				if [[ -n "${ERROR}" ]] ; then
					print_failed_flac
					printf "%s\n%s\n%s\n" \
						   "File:  ${i}" \
						   "Error: ${ERROR}" \
						   "------------------------------------------------------------------" \
						   >> "${VERIFY_ERRORS}"
				else
					metaflac --remove-tag=COMPRESSION "${i}"
					metaflac --set-tag=COMPRESSION=${COMPRESSION_LEVEL} "${i}"
					print_ok_flac
				fi
			# If already at COMPRESSION_LEVEL, test the FLAC file instead
			# or skip the file if '-C, --compress-notest' was specified
			else
				print_level_same_compression
				if [[ "${SKIP_TEST}" != "true" ]] ; then
					print_testing_flac
					ERROR="$((flac -ts "${i}") 2>&1)"
					if [[ -n "${ERROR}" ]] ; then
						print_failed_flac
						printf "%s\n%s\n%s\n" \
							   "File:  ${i}" \
							   "Error: ${ERROR}" \
							   "------------------------------------------------------------------" \
							   >> "${VERIFY_ERRORS}"
					else 
						print_ok_flac
					fi
				fi
			fi
		done
	}
	export -f compress_f

	# Run the above function with the configured threads (multithreaded)
	find "${DIRECTORY}" -name "*.[Ff][Ll][Aa][Cc]" -print0 | xargs -0 -n 1 -P "${CORES}" bash -c 'compress_f "${@}"' --
	
	if [[ -f "${VERIFY_ERRORS}" ]] ; then
		printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " Errors found in some FLAC files, please check:"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " \"${VERIFY_ERRORS}\" for errors"
		exit 1
	fi
}

################
#  TEST FLACS  #
################
# Test FLAC files
function test_flacs {
	title_testing_flac

	# Abort script and check for any errors thus far
	function test_abort {
		printf "\n%s${BOLD_GREEN}%s${NORMAL}%s\n" \
		" " "*" " Control-C received, exiting script..."
		if [[ -f "${TEST_ERRORS}" ]] ; then
			printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " Errors found in some FLAC files, please check:"
			printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " \"${TEST_ERRORS}\" for errors"
			exit 1
		fi
	}

	# Trap SIGINT (Control-C) to abort cleanly
	trap test_abort SIGINT

	function test_f {
		for i ; do
			print_testing_flac
			ERROR="$((flac -ts "${i}") 2>&1)"
			if [[ -n "${ERROR}" ]] ; then
				print_failed_flac
				printf "%s\n%s\n%s\n" \
					   "File:  ${i}" \
					   "Error: ${ERROR}" \
					   "------------------------------------------------------------------" \
					   >> "${TEST_ERRORS}"
			else
				print_ok_flac
			fi
		done
	}
	export -f test_f

	# Run the above function with the configured threads (multithreaded)
	find "${DIRECTORY}" -name "*.[Ff][Ll][Aa][Cc]" -print0 | xargs -0 -n 1 -P "${CORES}" bash -c 'test_f "${@}"' --

	if [[ -f "${TEST_ERRORS}" ]] ; then
		printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " Errors found in some FLAC files, please check:"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " \"${TEST_ERRORS}\" for errors"
		exit 1
	fi
}

#######################################
#  CHECK FLAC VALIDITY WITH AUCDTECT  #
#######################################
# Use auCDtect to check FLAC validity
function aucdtect {
	# Check if SPECTROGRAM_LOCATION is user-defined
	if [[ "${SPECTROGRAM_LOCATION}" != "default" ]] ; then
		# Put spectrograms in user-defined location
		# Test to make sure directory exists
		if [[ ! -d "${SPECTROGRAM_LOCATION}" ]] ; then
			printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " \"${SPECTROGRAM_LOCATION}\" doesn't exist!"
			printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " Please choose a valid directory under USER CONFIGURATION!"
			exit 1
		fi
	fi

	title_aucdtect_flac

	# Abort script and check for any errors thus far
	function aucdtect_abort {
		printf "\n%s${BOLD_GREEN}%s${NORMAL}%s\n" \
		" " "*" " Control-C received, exiting script..."

		# Don't remove WAV files in case user has WAV files there purposefully
		# The script cannot determine between existing and script-created WAV files
		WAV_FILES="$(find "${DIRECTORY}" -name "*.[Ww][Aa][Vv]" -print)"

		if [[ -f "${AUCDTECT_ERRORS}" ]] ; then
			printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " Some FLAC files may be lossy sourced, please check:"
			printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " \"${AUCDTECT_ERRORS}\" for details"
		fi

		if [[ -n "${WAV_FILES}" ]] ; then
			printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " There are some temporary WAV files leftover that"
			printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " couldn't be deleted because of script interruption"
			printf "\n%s${YELLOW}%s${NORMAL}%s\n" \
			" " "*" " This script cannot determine between existing WAV files"
			printf "%s${YELLOW}%s${NORMAL}%s\n" \
			" " "*" " and script-created files by design.  Please delete the"
			printf "%s${YELLOW}%s${NORMAL}%s\n" \
			" " "*" " below files manually:"

			# Display WAV files for manual deletion
			printf "%s\n" "${WAV_FILES}" | while read i ; do
				printf "%s${YELLOW}%s${NORMAL}%s\n" \
				" " "*" "    ${i}"
			done
		fi

		exit 1
	}
	
	# Trap SIGINT (Control-C) to abort cleanly
	trap aucdtect_abort SIGINT

	function aucdtect_f {
		for i ; do
			print_aucdtect_flac

			# Check if file is a FLAC file (variable hides output)
			CHECK_FLAC="$(metaflac --show-md5sum "${i}" 2>&1)"

			# If above command return anything other than '0', log output
			if [[ "${?}" -ne "0" ]] ; then
				printf "%s\n%s\n%s\n" \
					   "File:  ${i}" \
					   "Error: The above file does not appear to be a FLAC file" \
					   "------------------------------------------------------------------" \
					   >> "${AUCDTECT_ERRORS}"
				# File is not a FLAC file, display failed
				print_failed_flac
			else
				# Get the bit depth of a FLAC file
				BITS="$(metaflac --show-bps "${i}")"

				# Skip the FLAC file if it has a bit depth greater
				# than 16 since auCDtect doesn't support audio
				# files with a higher resolution than a CD.
				if [[ "${BITS}" -gt "16" ]] ; then
					print_aucdtect_skip
					printf "%s\n%s\n%s\n" \
						   "File:  ${i}" \
						   "Error: The above file has a bit depth greater than 16 and was skipped" \
						   "------------------------------------------------------------------" \
						   >> "${AUCDTECT_ERRORS}"
					continue
				fi

				# Decompress FLAC to WAV so auCDtect can read the audio file
				flac --totally-silent -d "${i}"

				# The actual auCDtect command with highest accuracy setting
				# 2> hides the displayed progress to /dev/null so nothing is shown
				AUCDTECT_CHECK="$("${AUCDTECT_COMMAND}" -m0 "${i%.[Ff][Ll][Aa][Cc]}.wav" 2> /dev/null)"

				# Reads the last line of the above command which tells what
				# auCDtect came up with for the WAV file
				ERROR="$(printf "%s" "${AUCDTECT_CHECK}" | tail -n1)"

				# There is an issue with the processed FLAC file
				if [[ "${ERROR}" != "This track looks like CDDA with probability 100%" ]] ; then
					# If user specified '-A, --aucdtect-spectrogram', then
					# create a spectrogram with SoX and change logging accordingly
					if [[ "${CREATE_SPECTROGRAM}" == "true" ]] ; then
						# Check whether to place spectrogram images in user-defined location
						if [[ "${SPECTROGRAM_LOCATION}" == "default" ]] ; then
							# Place images in same directory as the FLAC files
							# Make sure we don't clobber any picture files
							if [[ -f "${i%.[Ff][Ll][Aa][Cc]}.png" ]] ; then
								# File exists so prepend "spectrogram" before ".png"
								SPECTROGRAM_PICTURE="$(printf "%s" "${i%.[Ff][Ll][Aa][Cc]}.spectrogram.png")"
							else
								# File doesn't exist, so create the spectrogram with the basename of "$i"
								# with ".png" as the extension
								SPECTROGRAM_PICTURE="$(printf "%s" "${i%.[Ff][Ll][Aa][Cc]}.png")"
							fi
						else
							# Place images in user-defined location
							FLAC_FILE="$(printf "%s" "${i##*/}")"
							SPECTROGRAM_PICTURE="${SPECTROGRAM_LOCATION}/$(print "%s" "${FLAC_FILE%.[Ff][Ll][Aa][Cc]}.png")"
						fi

						# Let's create the spectrogram for the failed FLAC file
						# and output progress
						print_aucdtect_spectrogram

						# SoX command to create the spectrogram and place it in
						# SPECTROGRAM_PICTURE
						sox "${i}" -n spectrogram -c '' -t "${i}" -p1 -z90 -Z0 -q249 -wHann -x5000 -y1025 -o "${SPECTROGRAM_PICTURE}"

						# Print ISSUE and log error, and show where to find
						# the created spectrogram of processed FLAC file
						print_aucdtect_issue
						printf "%s\n%s\n%s\n%s\n" \
							   "File:        ${i}" \
							   "Error:       ${ERROR}" \
							   "Spectrogram: ${SPECTROGRAM_PICTURE}" \
							   "------------------------------------------------------------------" \
							   >> "${AUCDTECT_ERRORS}"
					else
						# Print ISSUE and log error
						print_aucdtect_issue
						printf "%s\n%s\n%s\n" \
							   "File:  ${i}" \
							   "Error: ${ERROR}" \
							   "------------------------------------------------------------------" \
							   >> "${AUCDTECT_ERRORS}"
					fi
				# The processed FLAC file is OK
				else
					print_ok_flac
				fi

				# Remove temporary WAV file
				rm "${i%.[Ff][Ll][Aa][Cc]}.wav"
			fi
		done
	}
	export -f aucdtect_f

	# Run the above function with the configured threads (multithreaded)
	find "${DIRECTORY}" -name "*.[Ff][Ll][Aa][Cc]" -print0 | xargs -0 -n 1 -P "${CORES}" bash -c 'aucdtect_f "${@}"' --

	if [[ -f "${AUCDTECT_ERRORS}" ]] ; then
		printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " Some FLAC files may be lossy sourced, please check:"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " \"${AUCDTECT_ERRORS}\" for details"
		exit 1
	fi
}

#########################
#  CHECK MD5 SIGNATURE  #
#########################
# Check for unset MD5 Signatures in FLAC files
function md5_check {
	title_md5check_flac

	# Abort script and check for any errors thus far
	function md5_check_abort {
		printf "\n%s${BOLD_GREEN}%s${NORMAL}%s\n" \
		" " "*" " Control-C received, exiting script..."
		if [[ -f "${MD5_ERRORS}" ]] ; then
			printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " The MD5 Signature is unset for some FLAC files or there were"
			printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " issues with some of the FLAC files, please check:"
			printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " \"${MD5_ERRORS}\" for details"
			exit 1
		fi
	}

	# Trap SIGINT (Control-C) to abort cleanly
	trap md5_check_abort SIGINT

	function md5_c {
		for i ; do
			print_checking_md5

			# Check if file is a FLAC file (variable hides output)
			MD5_SUM="$(metaflac --show-md5sum "${i}" 2>&1)"

			# If above command return anything other than '0', log output
			if [[ "${?}" -ne "0" ]] ; then
				print_failed_flac
				printf "%s\n%s\n%s\n" \
					   "File:  ${i}" \
					   "Error: The above file does not appear to be a FLAC file" \
					   "------------------------------------------------------------------" \
					   >> "${MD5_ERRORS}"
			elif [[ "${MD5_SUM}" == "00000000000000000000000000000000" ]] ; then
				print_failed_flac
				printf "%s\n%s\n%s\n" \
					   "File:  ${i}" \
					   "Error: MD5 Signature unset (${MD5_SUM})" \
					   "------------------------------------------------------------------" \
					   >> "${MD5_ERRORS}"
			else
				print_ok_flac
			fi
		done
	}
	export -f md5_c

	# Run the above function with the configured threads (multithreaded)
	find "${DIRECTORY}" -name "*.[Ff][Ll][Aa][Cc]" -print0 | xargs -0 -n 1 -P "${CORES}" bash -c 'md5_c "${@}"' --
	
	if [[ -f "${MD5_ERRORS}" ]] ; then
		printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " The MD5 Signature is unset for some FLAC files or there were"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " issues with some of the FLAC files, please check:"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " \"${MD5_ERRORS}\" for details"
		exit 1
	fi  
}

###############
#  REDO TAGS  #
###############
# If COVERART tag is kept and REMOVE_ARTWORK is set to 'true'
# display conflict and exit
function coverart_remove_conflict {
	# Check if COVERART exists in the tag array.  Notify user
	# of its deprecation and advise against using it, preferring
	# METADATA_BLOCK_PICTURE
	for j in "${tags[@]}" ; do
		if [[ "${j}" == "COVERART" ]] ; then
			# If REMOVE_ARTWORK is "true" (remove the artwork), then
			# exit and warn the user you can't specify whether you want to
			# remove artwork, yet keep the COVERART tag in USER CONFIGURATION
			if [[ "${REMOVE_ARTWORK}" == "true" ]] ; then
				# Display COVERART tag warning
				coverart_warning

				printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
				" " "*" " It appears you have REMOVE_ARTWORK set to \"true\" under"
				printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
				" " "*" " USER CONFIGURATION, yet COVERART is specified as one"
				printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
				" " "*" " (or more) of the FLAC tags to be kept. Please choose either"
				printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
				" " "*" " keep album artwork (ie REMOVE_ARTWORK=\"false\") or remove"
				printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
				" " "*" " the COVERART tag under the USER CONFIGURATION portion of this"
				printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
				" " "*" " script."
				exit 1
			# COVERART was found, but artwork is to be removed,
			# so warn user
			else
				# Create COVERART_WARNING variable, so script can append
				# the coverart_warning function after completion as well as
				# determine the correct tag array to use (whether we should
				# add COVERART or not)
				COVERART_WARNING="true"

				# Display tag field warning
				countdown_metadata
			fi
		fi
	done

	# COVERART wasn't found and REMOVE_ARTWORK is set to 'true'
	if [[ "${COVERART_WARNING}" != "true" ]] ; then
		countdown_metadata
	fi
}

# Display why COVERART tag should not be used
function coverart_warning {
	printf "\n%s${YELLOW}%s${NORMAL}%s\n" \
	" " "*" " The COVERART tag is deprecated and should not be"
	printf "%s${YELLOW}%s${NORMAL}%s\n" \
	" " "*" " used. Instead, consider migrating over to the new format:"
	printf "%s${YELLOW}%s${NORMAL}%s\n" \
	" " "*" " METADATA_BLOCK_PICTURE, using modern tag editors. Read:"
	printf "%s${YELLOW}%s${NORMAL}%s\n" \
	" " "*" " http://wiki.xiph.org/VorbisComment#Unofficial_COVERART_field_.28deprecated.29"
	printf "%s${YELLOW}%s${NORMAL}%s\n" \
	" " "*" " for more details."
}

# Check for missing tags and retag FLAC files if all files
# are not missing tags
function redo_tags {
	# Keep SIGINT from exiting the script (Can cause all tags
	# to be lost if done when tags are being removed!)
	trap '' SIGINT

	################
	# ANALYZE TAGS #
	################

	function analyze_tags {
		# Check if file is a FLAC file (variable hides output)
		CHECK_FLAC="$(metaflac --show-md5sum "${i}" 2>&1)"

		# If above command return anything other than '0', log output
		if [[ "${?}" -ne "0" ]] ; then
			printf "%s\n%s\n%s\n" \
				  "File:  ${i}" \
				  "Error: The above file does not appear to be a FLAC file" \
				  "------------------------------------------------------------------" \
				  >> "${METADATA_ERRORS}"
			# File is not a FLAC file, display failed
			print_failed_flac
		else
			# Recreate the tags array so it can be used by the child process
			eval "tags=(${EXPORT_TAG[*]})"

			# Iterate through each tag field and check if tag is missing
			for j in "${tags[@]}" ; do
				# Check if ALBUMARTIST is in tag array and apply operations on
				# the tag field if it exists
				if [[ "${j}" == [Aa][Ll][Bb][Uu][Mm][Aa][Rr][Tt][Ii][Ss][Tt] ]] ; then
					# ALBUMARTIST exists in tag array so allow script to check the
					# various naming conventions within the FLAC files (ie,
					# 'album artist' or 'album_artist')

					# "ALBUMARTIST"
					if [[ -n "$(metaflac --show-tag=ALBUMARTIST "${i}")" ]] ; then
						# Set a temporary variable to be easily parsed by `eval`
						local TEMP_TAG="$(metaflac --show-tag=ALBUMARTIST "${i}")"
						local TEMP_TAG="${TEMP_TAG/#*=}"
					# "album artist"
					elif [[ -n "$(metaflac --show-tag="album artist" "${i}")" ]] ; then
						# Set a temporary variable to be easily parsed by `eval`
						local TEMP_TAG="$(metaflac --show-tag="album artist" "${i}")"
						local TEMP_TAG="${TEMP_TAG/#*=}"
					# "album_artist"
					elif [[ -n "$(metaflac --show-tag="album_artist" "${i}")" ]] ; then
						# Set a temporary variable to be easily parsed by `eval`
						local TEMP_TAG="$(metaflac --show-tag="album_artist" "${i}")"
						local TEMP_TAG="${TEMP_TAG/#*=}"
					fi
				else
					# Set a temporary variable to be easily parsed by `eval`
					local TEMP_TAG="$(metaflac --show-tag="${j}" "${i}")"
					local TEMP_TAG="${TEMP_TAG/#*=}"
				fi

				# Evaluate TEMP_TAG into the dynamic tag
				eval "${j}"_TAG='"${TEMP_TAG}"'

				# If tags are not found, log output
				if [[ -z "$(eval "printf "%s" "\$${j}_TAG"")" ]] ; then
					printf "%s\n%s\n%s\n" \
						   "File:  ${i}" \
						   "Error: ${j} tag not found" \
						   "------------------------------------------------------------------" \
						   >> "${METADATA_ERRORS}"
				fi
			done
		fi
	}
	export -f analyze_tags

	function analyze_tags_dont_log_coverart {
		# Check if file is a FLAC file (variable hides output)
		CHECK_FLAC="$(metaflac --show-md5sum "${i}" 2>&1)"

		# If above command return anything other than '0', log output
		if [[ "${?}" -ne "0" ]] ; then
			printf "$%s\n%s\n%s\n" \
				   "File:  ${i}" \
				   "Error: The above file does not appear to be a FLAC file" \
				   "------------------------------------------------------------------" \
				   >> "${METADATA_ERRORS}"
			# File is not a FLAC file, display failed
			print_failed_flac
		else
			# Recreate the tags array so it can be used by the child process
			eval "tags=(${EXPORT_TAG[*]})"

			# Album artwork is to be kept so preserve COVERART
			tags=( "${tags[@]}" COVERART )

			# Iterate through each tag field and check if tag is missing (except
			# for the COVERART tag)
			for j in "${tags[@]}" ; do
				# Check if ALBUMARTIST is in tag array and apply operations on
				# the tag field if it exists
				if [[ "${j}" == [Aa][Ll][Bb][Uu][Mm][Aa][Rr][Tt][Ii][Ss][Tt] ]] ; then
					# ALBUMARTIST exists in tag array so allow script to check the
					# various naming conventions within the FLAC files (ie,
					# 'album artist' or 'album_artist')

					# "ALBUMARTIST"
					if [[ -n "$(metaflac --show-tag=ALBUMARTIST "${i}")" ]] ; then
						# Set a temporary variable to be easily parsed by `eval`
						local TEMP_TAG="$(metaflac --show-tag=ALBUMARTIST "${i}")"
						local TEMP_TAG="${TEMP_TAG/#*=}"
					# "album artist"
					elif [[ -n "$(metaflac --show-tag="album artist" "${i}")" ]] ; then
						# Set a temporary variable to be easily parsed by `eval`
						local TEMP_TAG="$(metaflac --show-tag="album artist" "${i}")"
						local TEMP_TAG="${TEMP_TAG/#*=}"
					# "album_artist"
					elif [[ -n "$(metaflac --show-tag="album_artist" "${i}")" ]] ; then
						# Set a temporary variable to be easily parsed by `eval`
						local TEMP_TAG="$(metaflac --show-tag="album_artist" "${i}")"
						local TEMP_TAG="${TEMP_TAG/#*=}"
					fi
				else
					# Set a temporary variable to be easily parsed by `eval`
					local TEMP_TAG="$(metaflac --show-tag="${j}" "${i}")"
					local TEMP_TAG="${TEMP_TAG/#*=}"
				fi

				# Evaluate TEMP_TAG into the dynamic tag
				eval "${j}"_TAG='"${TEMP_TAG}"'

				# If COVERART_TAG is not null, then log file that has
				# the COVERART tag embedded within it about deprecation
				if [[ -n "${COVERART_TAG}" ]] ; then
					printf "%s\n%s\n%s\n%s\n" \
						   "File:  ${i}" \
						   "Error: \"${j}\" tag is DEPRECATED in above file. Consider migrating to" \
						   "       the new format: METADATA_BLOCK_PICTURE." \
						   "------------------------------------------------------------------" \
						   >> "${METADATA_ERRORS}"
				fi

				# If tags are not found, log output. Skip output
				# of COVERART tag as this is a temporary addition to
				# the tag array (for processing legacy artwork)
				if [[ -z "$(eval "printf "%s" "\$${j}_TAG"")" && "${j}" != "COVERART" ]] ; then
					printf "%s\n%s\n%s\n" \
						   "File:  ${i}" \
						   "Error: ${j} tag not found" \
						   "------------------------------------------------------------------" \
						   >> "${METADATA_ERRORS}"
				fi
			done
		fi
	}
	export -f analyze_tags_dont_log_coverart

	# If COVERART was specified under USER CONFIGURATION
	# set the tag array accordingly and test whether there
	# are missing tags in each FLAC file
	if [[ "${COVERART_WARNING}" == "true" ]] ; then
		title_analyze_tags

		# COVERART is already in the tag array. Implies album
		# artwork is to be kept, so log if COVERART tag is missing
		# Function check_tags to allow multithreading
		function check_tags {
			for i ; do
				# Print script operation title
				print_analyzing_tags

				# Analyze FLACs for missing tags
				analyze_tags

				# Done analyzing FLAC file tags
				print_done_flac
			done
		}
		export -f check_tags
	else
		# COVERART is not in the tag array, so add it if album artwork
		# is to be kept
		if [[ "${REMOVE_ARTWORK}" == "false" ]] ; then
			title_analyze_tags

			# Analyze tags but don't log COVERART is missing tag
			# Function check_tags to allow multithreading
			function check_tags {
				for i ; do
					# Print script operation title
					print_analyzing_tags

					# Analyze FLACs for missing tags
					# (except for COVERART tag)
					analyze_tags_dont_log_coverart

					# Done analyzing FLAC file tags
					print_done_flac
				done
			}
			export -f check_tags
		else
			title_analyze_tags

			# Album artwork is NOT kept, so process tag fields, omitting COVERART
			# Function check_tags to allow multithreading
			function check_tags {
				for i ; do
					# Print script operation title
					print_analyzing_tags

					# Analyze FLACs for missing tags
					analyze_tags

					# Done analyzing FLAC file tags
					print_done_flac
				done
			}
			export -f check_tags
		fi
	fi

	# Run the "check_tags" function with the configured threads (multithreaded)
	find "${DIRECTORY}" -name "*.[Ff][Ll][Aa][Cc]" -print0 | xargs -0 -n 1 -P "${CORES}" bash -c 'check_tags "${@}"' --

	# Test for DEPRECATED tag, COVERART in METADATA_ERROR log.  If it
	# exists, set COVERART_WARNING variable to make script output
	# warning upon completion
	if [[ -f "${METADATA_ERRORS}" ]] ; then
		while read i ; do
			# Indentation is culled from reading in "${i}"
			# To change this, set IFS to '\n'
			if [[ "${i}" == "the new format: METADATA_BLOCK_PICTURE." ]] ; then
				COVERART_WARNING="true"
				break
			fi
		done < "${METADATA_ERRORS}"
	fi

	if [[ -f "${METADATA_ERRORS}"  && "${COVERART_WARNING}" == "true" ]] ; then
		# Display COVERART warning function and metadata issues
		printf ''
		coverart_warning
		printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " Some FLAC files have missing tags or there were"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " issues with some of the FLAC files, please check:"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " \"${METADATA_ERRORS}\" for details."
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " Not Re-Tagging files."
		exit 1
	elif [[ -f "${METADATA_ERRORS}" ]] ; then
		# Just display metadata issues
		printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " Some FLAC files have missing tags or there were"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " issues with some of the FLAC files, please check:"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " \"${METADATA_ERRORS}\" for details."
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " Not Re-Tagging files."
		exit 1
	fi

	############
	# SET TAGS #
	############

	# Recreate the tags array as it may have added the
	# COVERART tag.  This way, we ensure that the COVERART
	# tag is, in fact, temporary.
	eval "tags=(${EXPORT_TAG[*]})"

	title_setting_tags

	# Set the FLAC metadata to each FLAC file
	function remove_set_tags {
		# Iterate through the tag array and set a variable for each tag
		for j in "${tags[@]}" ; do
			# Check if ALBUMARTIST is in tag array and apply operations on
			# the tag field if it exists
			if [[ "${j}" == [Aa][Ll][Bb][Uu][Mm][Aa][Rr][Tt][Ii][Ss][Tt] ]] ; then
				# ALBUMARTIST exists in tag array so allow script to check the
				# various naming conventions within the FLAC files (ie,
				# 'album artist' or 'album_artist')

				# "ALBUMARTIST"
				if [[ -n "$(metaflac --show-tag=ALBUMARTIST "${i}")" ]] ; then
					# Set a temporary variable to be easily parsed by `eval`
					local TEMP_TAG="$(metaflac --show-tag=ALBUMARTIST "${i}")"
					local TEMP_TAG="${TEMP_TAG/#*=}"
				# "album artist"
				elif [[ -n "$(metaflac --show-tag="album artist" "${i}")" ]] ; then
					# Set a temporary variable to be easily parsed by `eval`
					local TEMP_TAG="$(metaflac --show-tag="album artist" "${i}")"
					local TEMP_TAG="${TEMP_TAG/#*=}"
				# "album_artist"
				elif [[ -n "$(metaflac --show-tag="album_artist" "${i}")" ]] ; then
					# Set a temporary variable to be easily parsed by `eval`
					local TEMP_TAG="$(metaflac --show-tag="album_artist" "${i}")"
					local TEMP_TAG="${TEMP_TAG/#*=}"
				fi
			else
				# Set a temporary variable to be easily parsed by `eval`
				local TEMP_TAG="$(metaflac --show-tag="${j}" "${i}")"
				local TEMP_TAG="${TEMP_TAG/#*=}"
			fi

			# Evaluate TEMP_TAG into the dynamic tag
			eval "${j}"_SET='"${TEMP_TAG}"'
		done
	
		# Remove all the tags
		metaflac --remove --block-type=VORBIS_COMMENT "${i}"

		# Iterate through the tag array and add the saved tags back
		for j in "${tags[@]}" ; do
			metaflac --set-tag="${j}"="$(eval "printf "%s" \$${j}_SET")" "${i}"
		done
	}
	export -f remove_set_tags

	# Function retag_flacs to allow multithreading
	function retag_flacs {
		# Recreate the tags array so it can be used by the child process
		eval "tags=(${EXPORT_TAG[*]})"
		for i ; do
			print_setting_tags
			remove_set_tags
			print_ok_flac
		done
	}
	export -f retag_flacs
	
	# Run the above function with the configured threads (multithreaded)
	find "${DIRECTORY}" -name "*.[Ff][Ll][Aa][Cc]" -print0 | xargs -0 -n 1 -P "${CORES}" bash -c 'retag_flacs "${@}"' --
}

#################
#  PRUNE FLACS  #
#################
# Clear excess FLAC metadata from each FLAC file
function prune_flacs {
	title_prune_flac

	# Abort script and check for any errors thus far
	function prune_abort {
		printf "\n%s${BOLD_GREEN}%s${NORMAL}%s\n" \
		" " "*" " Control-C received, exiting script..."
		if [[ -f "${PRUNE_ERRORS}" ]] ; then
			printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " There were issues with some of the FLAC files,"
			printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " please check:"
			printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " \"${PRUNE_ERRORS}\" for details."
			exit 1
		fi
	}

	# Trap SIGINT (Control-C) to abort cleanly	
	trap prune_abort SIGINT

	function prune_f {
		# Don't remove artwork if user wants it kept.  We don't have to check
		# for the legacy COVERART tag as we are NOT removing any VORBIS_COMMENTs.
		if [[ "${REMOVE_ARTWORK}" == "true" ]] ; then
			# Remove artwork (exported for subshell access)
			export DONT_PRUNE_FLAC_METADATA="STREAMINFO,VORBIS_COMMENT"
		else
			# Don't remove artwork (exported for subshell access)
			export DONT_PRUNE_FLAC_METADATA="STREAMINFO,PICTURE,VORBIS_COMMENT"
		fi

		for i ; do
			print_prune_flac

			# Check if file is a FLAC file (variable hides output)
			CHECK_FLAC="$(metaflac --show-md5sum "${i}" 2>&1)"

			# If above command return anything other than '0', log output
			if [[ "${?}" -ne "0" ]] ; then
				printf "%s\n%s\n%s\n" \
					   "File:  ${i}" \
					   "Error: The above file does not appear to be a FLAC file" \
					   "------------------------------------------------------------------" \
					   >> "${PRUNE_ERRORS}"
				# File is not a FLAC file, display failed
				print_failed_flac
			else
				# Remove all information but STREAMINFO,VORBIS_COMMENTs, and
				# possibly METADATA_BLOCK_PICTURE
				metaflac --remove --dont-use-padding --except-block-type="${DONT_PRUNE_FLAC_METADATA}" "${i}"
				print_ok_flac
			fi
		done
	}
	export -f prune_f
	
	# Run the above function with the configured threads (multithreaded)
	find "${DIRECTORY}" -name "*.[Ff][Ll][Aa][Cc]" -print0 | xargs -0 -n 1 -P "${CORES}" bash -c 'prune_f "${@}"' --

	if [[ -f "${PRUNE_ERRORS}" ]] ; then
		printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " There were issues with some of the FLAC files,"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " please check:"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " \"${PRUNE_ERRORS}\" for details."
	fi
}

#######################
#  DISPLAY LONG HELP  #
#######################
# Display a lot of help
function long_help {
# Keep the ${LONG_HELP} variable from garbling
# the text spacing
OLDIFS="${IFS}"
IFS='\n'

LONG_HELP="  Usage: ${0} [OPTION] [OPTION]... [PATH_TO_FLAC(s)]
  Options:
    -c, --compress
           Compress the FLAC files with the user-specified level of compression
           defined under USER CONFIGURATION (as the variable COMPRESSION_LEVEL)
           and verify the resultant files.

           The default is 8, with the range of values starting from 1 to 8 with
           the smallest compression at 1, and the highest at 8.  This option
           will add a tag to all successfully verified FLAC files.  Below
           shows the default COMPRESSION tag added to each successfully
           verified FLAC:

                       COMPRESSION=8

           If any FLAC files already have the defined COMPRESSION_LEVEL tag (a
           good indicator the files are already compressed at that level), the
           script will instead test the FLAC files for any errors.  This is useful
           to check your entire music library to make sure all the FLAC files are
           compressed at the level specified as well as make sure they are intact.

           If any files are found to be corrupt, this script will quit upon
           finishing the compression of any other files and produce an error
           log.

    -C, --compress-notest
           Same as the '--compress' option, but if any FLAC files already have the
           defined COMPRESSION_LEVEL tag, the script will skip the file and continue
           on to the next without test the FLAC file's integrity.  Useful for
           checking all your FLAC files are compressed at the level specified.

    -t, --test
           Same as compress but instead of compressing the FLAC files, this
           script just verfies the files.  This option will NOT add the
           COMPRESSION tag to the files.

           As with the '--compress' option, this will produce an error log if
           any FLAC files are found to be corrupt.

    -a, --aucdtect
           Uses the auCDtect program by Oleg Berngardt and Alexander Djourik to
           analyze FLAC files and check with fairly accurate precision whether
           the FLAC files are lossy sourced or not.  For example, an MP3 file
           converted to FLAC is no longer lossless therefore lossy sourced.

           While this program isn't foolproof, it gives a good idea which FLAC
           files will need further investigation (ie a spectrogram).  This program
           does not work on FLAC files which have a bit depth more than a typical
           audio CD (16bit), and will skip the files that have a higher bit depth.

           If any files are found to not be perfect (100% CDDA), a log will be created
           with the questionable FLAC files recorded in it.

    -A, --aucdtect-spectrogram
           Same as '-a, --aucdtect' with the addition of creating a spectrogram for
           each FLAC file that fails auCDtect, that is, any FLAC file that does not
           return 100% CDDA from auCDtect will be scanned and a spectrogram will be
           created.

           Any FLAC file skipped (due to having a higher bit depth than 16), will
           NOT have a spectrogram created.

           By default, each spectrogram will be created in the same folder as the
           tested FLAC file with the same name as the tested FLAC file:

               03 - Some FLAC File.flac --> 03 - Some FLAC File.png

           If there already is a PNG file with the same name as the tested FLAC,
           the name 'spectrogram' will prepend the '.png' extension:

               03 - Some FLAC File.flac --> 03 - Some FLAC File.spectrogram.png

           The user can change the location of where to store the created
           spectrogram images by changing the value of SPECTROGRAM_LOCATION under
           the USER CONFIGURATION section of this script.  The location defined by
           the user will be tested to see if it exists before starting the script.
           If the location does NOT exist, the script will warn the user and exit.

           The created PNG file is large in resolution to best capture the
           FLAC file's waveform (roughly 5140x2149).

           The spectrogram is created using the program SoX.  If the user tries
           to use this option without having SoX installed, the script will warn
           the user that SoX is missing and exit.

    -m, --md5check
           Check the FLAC files for unset MD5 Signatures and log the output of
           any unset signatures.  An unset MD5 signature doesn't necessarily mean
           a FLAC file is corrupt, and can be repaired with a re-encoding of said
           FLAC file.

    -p, --prune
           Delete every METADATA block in each FLAC file except the STREAMINFO and
           VORBIS_COMMENT block.  If REMOVE_ARTWORK is set to 'false', then the
           PICTURE block will NOT be removed.

    -g, --replaygain
           Add ReplayGain tags to the FLAC files.  The ReplayGain is calculated
           for ALBUM and TRACK values. ReplayGain is applied via VORBIS_TAGS and
           as such, will require the redo, '--r argument' to have these tags kept
           in order to preserve the added ReplayGain values.  The tags added are:

                      REPLAYGAIN_REFERENCE_LOUDNESS
                      REPLAYGAIN_TRACK_GAIN
                      REPLAYGAIN_TRACK_PEAK
                      REPLAYGAIN_ALBUM_GAIN
                      REPLAYGAIN_ALBUM_PEAK

           In order for the ReplayGain values to be applied correctly, the
           script has to determine which FLAC files to add values by directory.
           What this means is that the script must add the ReplayGain values by
           working off the FLAC files' parent directory.  If there are some FLAC
           files found, the script will move up one directory and begin applying
           the ReplayGain values.  This is necessary in order to get the
           REPLAYGAIN_ALBUM_GAIN and REPLAYGAIN_ALBUM_PEAK values set correctly.
           Without doing this, the ALBUM and TRACK values would be identical.

           Ideally, this script would like to be able to apply the values on each
           FLAC file individually, but due to how metaflac determines the
           ReplayGain values for ALBUM values (ie with wildcard characters), this
           isn't simple and/or straightforward.

           A limitation of this option can now be seen.  If a user has many FLAC
           files under one directory (of different albums/artists), the
           ReplayGain ALBUM values are going to be incorrect as the script will
           perceive all those FLAC files to essentially be an album.  For now,
           this is mitigated by having your music library somewhat organized with
           each album housing the correct FLAC files and no others.

           In the future, this script will ideally choose which FLAC files will
           be processed by ARTIST and ALBUM metadata, not requiring physical
           directories to process said FLAC files.

           Due to the nature of how ALBUM values are processed, this option cannot
           use more than one thread, so the CORES configuration option will not be
           honored -- enforcing only one thread.

           If there are any errors found while creating the ReplayGain values
           and/or setting the values, an error log will be produced.

    -r, --redo
           Extract the configured tags in each FLAC file and clear the rest before
           retagging the file.  The default tags kept are:

                      TITLE
                      ARTIST
                      ALBUM
                      DISCNUMBER
                      DATE
                      TRACKNUMBER
                      TRACKTOTAL
                      GENRE
                      COMPRESSION
                      RELEASETYPE
                      SOURCE
                      MASTERING
                      REPLAYGAIN_REFERENCE_LOUDNESS
                      REPLAYGAIN_TRACK_GAIN
                      REPLAYGAIN_TRACK_PEAK
                      REPLAYGAIN_ALBUM_GAIN
                      REPLAYGAIN_ALBUM_PEAK

           If any FLAC files have missing tags (from those configured to be kept),
           the file and the missing tag will be recorded in a log.

           The tags that can be kept are eseentially infinite, as long as the
           tags to be kept are set in the tag configuration located at the top of
           this script under USER CONFIGURATION.

           If this option is specified, a warning will appear upon script
           execution.  This warning will show which of the configured TAG fields
           to keep when re-tagging the FLAC files.  A countdown will appear
           giving the user 10 seconds to abort the script, after which, the script
           will begin running it's course.

    -l, --all
           This option is short for:

                      -c, --compress
                      -m, --md5check
                      -p, --prune
                      -g, --replaygain
                      -r, --redo

           If any of these options (or variations of the above options) are called, this
           script will warn the user of conflicting options and exit.

    -L, --reallyall
           This option is short for:

                      -c, --compress
                      -m, --md5check
                      -p, --prune
                      -g, --replaygain
                      -r, --redo
                      -A, --aucdtect-spectrogram

           If any of these options (or variations of the above options) are called, this
           script will warn the user of conflicting options and exit.

    -n, --no-color
           Turn off color output.

    -v, --version
           Display script version and exit.

    -h, --help
           Shows this help message.

           This script can use more than one CPU/Cores (threads).  By default, this script will
           use two (2) threads, which can be configured under USER CONFIGURATION (located near the top
           of this script).

           Multithreading is achieved by utilizing the 'xargs' command which comes bundled with the
           'find' command.  While not true multithreading, this psuedo multithreading will greatly speed
           up the processing if the host has more than one CPU.


  Invocation Examples:
    # Compress and verify FLAC files
    ${0} --compress /media/Music_Files

    # Same as above but check MD5 Signature of all FLAC files if all files are verified as OK
    # from previous command
    ${0} -c -m Music/FLACS    <--- **RELATIVE PATHS ALLOWED**

    # Same as above but remove the SEEKTABLE and excess PADDING in all of the FLAC files if all
    # files are verified as OK from previous command
    ${0} -c -m -p /some/path/to/files

    # Same as above but with long argument notation
    ${0} --compress --md5check --prune /some/path/to/files

    # Same as above but with mixed argument notation
    ${0} --compress -m -p /some/path/to/files

    # Clear excess tags from each FLAC file
    ${0} --redo /some/path/to/files

    # Compress FLAC files and redo the FLAC tags
    ${0} -c -r /some/path/to/files"

# Restore IFS
IFS="${OLDIFS}"

# Print out help (will be piped to ${PAGER} elsewhere)
printf "%s\n" "${LONG_HELP}"
}

########################
#  DISPLAY SHORT HELP  #
########################
# Display short help
function short_help {
	printf "%s\n" "  Usage: ${0} [OPTION] [OPTION]... [PATH_TO_FLAC(s)]"
	printf "%s\n" "  Options:"
	printf "%s\n" "    -c, --compress"
	printf "%s\n" "    -C, --compress-notest"
	printf "%s\n" "    -t, --test"
	printf "%s\n" "    -m, --md5check"
	printf "%s\n" "    -a, --aucdtect"
	printf "%s\n" "    -A, --aucdtect-spectrogram"
	printf "%s\n" "    -p, --prune"
	printf "%s\n" "    -g, --replaygain"
	printf "%s\n" "    -r, --redo"
	printf "%s\n" "    -l, --all"
	printf "%s\n" "    -L, --reallyall"
	printf "%s\n" "    -n, --no-color"
	printf "%s\n" "    -v, --version"
	printf "%s\n" "    -h, --help"
	printf "%s\n" "  This is the short help; for details use '${0} --help' or '${0} -h'"
}

############################
#  DISPLAY SCRIPT VERSION  #
############################
# Display script version
function print_version {
	printf "%s\n" "Version ${VERSION}"
}

#######################
#  PRE-SCRIPT CHECKS  #
#######################
# Add case where only one argument is specified
if [[ "${#}" -eq 1 ]] ; then
	case "${1}" in
		--version|-v)
			print_version
			exit 0
			;;
		--help|-h)
			# Check for ${PAGER}. If a pager is available
			# lets use it. If not, just display help
			if [[ -n "${PAGER}" ]] ; then
				long_help | "${PAGER}"
				exit 0
			else
				long_help
				exit 0
			fi
			;;
		*)
			short_help
			exit 0
			;;
	esac
fi

# Handle various command switches
while [[ "${#}" -gt 1 ]] ; do
	case "${1}" in
		--all|-l)
			ALL="true"
			shift
			;;
		--reallyall|-L)
			REALLYALL="true"
			shift
			;;
		--compress|-c)
			COMPRESS="true"
			COMPRESS_TEST="true"
			shift
			;;
		--compress-notest|-C)
			COMPRESS="true"
			export SKIP_TEST="true"
			shift
			;;
		--test|-t)
			TEST="true"
			shift
			;;
		--replaygain|-g)
			REPLAYGAIN="true"
			shift
			;;
		--aucdtect|-a)
			AUCDTECT="true"
			# Not used in subshell(s)
			NO_SPECTROGRAM="true"
			shift
			;;
		--aucdtect-spectrogram|-A)
			AUCDTECT="true"
			export CREATE_SPECTROGRAM="true"
			shift
			;;
		--md5check|-m)
			MD5CHECK="true"
			shift
			;;
		--prune|-p)
			PRUNE="true"
			shift
			;;
		--redo|-r)
			REDO="true"
			shift
			;;
		--no-color|-n)
			NO_COLOR="true"
			shift
			;;
		*)
			short_help
			exit 0
			;;
	esac
done

# This must come before the other options in
# order for it to take effect
if [[ "${NO_COLOR}" == "true" ]] ; then
	BOLD_GREEN=""
	BOLD_RED=""
	BOLD_BLUE=""
	CYAN=""
	NORMAL=""
	YELLOW=""
fi

# Check to make sure script has all the dependencies
# necessary to complete script succesfully
# Check if each command can be found in $PATH
SLEEP_EXISTS="$(command -v sleep)"
STTY_EXISTS="$(command -v stty)"
FIND_EXISTS="$(command -v find)"
XARGS_EXISTS="$(command -v xargs)"
METAFLAC_EXISTS="$(command -v metaflac)"
FLAC_EXISTS="$(command -v flac)"

# Go through and test if each command was found (by displaying its $PATH).  If
# it's empty, add where you can find the package to an array to be displayed.
if [[ -z "${SLEEP_EXISTS}" ]] ; then
	command_exists_array=( "${command_exists_array[@]}" "You can generally install \"sleep\" with the \"coreutils\" package." )
fi

if [[ -z "${STTY_EXISTS}" ]] ; then
	command_exists_array=( "${command_exists_array[@]}" "You can generally install \"stty\" with the \"coreutils\" package." )
fi

if [[ -z "${FIND_EXISTS}" ]] ; then
	command_exists_array=( "${command_exists_array[@]}" "You can generally install \"find\" with the \"findutils\" package." )
fi

if [[ -z "${XARGS_EXISTS}" ]] ; then
	command_exists_array=( "${command_exists_array[@]}" "You can generally install \"xargs\" with the \"findutils\" package." )
fi

if [[ -z "${METAFLAC_EXISTS}" ]] ; then
	command_exists_array=( "${command_exists_array[@]}" "You can generally install \"metaflac\" with the \"flac\" package." )
fi

if [[ -z "${FLAC_EXISTS}" ]] ; then
	command_exists_array=( "${command_exists_array[@]}" "You can generally install \"flac\" with the \"flac\" package." )
fi

# Display (in bold red) message that system is missing vital programs
function display_missing_commands_header {
	printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
	" " "*" " You seem to be missing one or more necessary programs"
	printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
	" " "*" " to run this script reliably.  Below shows the program(s)"
	printf "%s${BOLD_RED}%s${NORMAL}%s\n\n" \
	" " "*" " missing, as well as where you can install them from:"
}

# If all the programs above were found, continue with script.  Else
# display warning and exit script, printing out which package has
# the missing programs
if [[ -n "${command_exists_array[@]}" ]] ; then
	display_missing_commands_header
	# Iterate through array and print each value
	for i in "${command_exists_array[@]}" ; do
		printf "%s${YELLOW}%s${NORMAL}%s\n" \
		" " "*" " ${i}"
	done
	exit 1
fi

# Set the last argument as the directory
DIRECTORY="${1}"

# Check whether DIRECTORY is not null and whether the directory exists
if [[ -n "${DIRECTORY}" && ! -d "${DIRECTORY}" ]] ; then
	printf "%s\n" "  Usage: ${0} [OPTION] [PATH_TO_FLAC(s)]..."
	printf "\n%s${BOLD_RED}%s${NORMAL}%s\n" \
	" " "*" " Please specify a directory!"
	exit 1
fi

# If no arguments are made to the script show usage
if [[ "${#}" -eq 0 ]] ; then
	short_help
	exit 0
fi

# If "-l, --all" and "-L, --reallyall" are both called, warn and exit
if [[ "${ALL}" == "true" && "${REALLYALL}" == "true" ]] ; then
	printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
	" " "*" " Running both \"-l, --all\" and \"-L, --reallyall\" conflict!"
	printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
	" " "*" " Please choose one or the other." 
	exit 1
fi

# If "-l, --all" or "-L, --reallyall" was called, check if arguments
# were called that already will be performed by the above argument(s).
# If any were called, display a warning and exit the script
if [[ "${ALL}" == "true" || "${REALLYALL}" == "true" ]] ; then

	# Check for "-c, --compress".  If used add it to array
	if [[ "${COMPRESS}" == "true" && "${SKIP_TEST}" == "false" ]] ; then
		argumentConflict=( "${argumentConflict[@]}" "-c, --compress" )
	# Check for "-C, --compress-notest".  If used add it to array
	elif [[ "${COMPRESS}" == "true" && "${SKIP_TEST}" == "true" ]] ; then
		argumentConflict=( "${argumentConflict[@]}" "-C, --compress-notest" )
	fi

	# Check for "-t, --test".  If used add it to array
	if [[ "${TEST}" == "true" ]] ; then
		argumentConflict=( "${argumentConflict[@]}" "-t, --test" )
	fi

	# Check for "-m, --md5check".  If used add it to array
	if [[ "${MD5CHECK}" == "true" ]] ; then
		argumentConflict=( "${argumentConflict[@]}" "-m, --md5check" )
	fi

	# Check for "-p, --prune".  If used add it to array
	if [[ "${PRUNE}" == "true" ]] ; then
		argumentConflict=( "${argumentConflict[@]}" "-p, --prune" )
	fi

	# Check for "-g, --replaygain".  If used add it to array
	if [[ "${REPLAYGAIN}" == "true" ]] ; then
		argumentConflict=( "${argumentConflict[@]}" "-g, --replaygain" )
	fi

	# Check for "-r, --redo".  If used add it to array
	if [[ "${REDO}" == "true" ]] ; then
		argumentConflict=( "${argumentConflict[@]}" "-r, --redo" )
	fi

	# If "-L, --reallyall" was called, check for the various forms of calling
	# auCDtect.  If it was called, add it to array
	if [[ "${REALLYALL}" == "true" ]] ; then
		if [[ "${AUCDTECT}" == "true" && "${CREATE_SPECTROGRAM}" == "true" ]] ; then
			argumentConflict=( "${argumentConflict[@]}" "-A, --aucdtect-spectrogram" )
		elif [[ "${AUCDTECT}" == "true" && "${CREATE_SPECTROGRAM}" != "true" ]] ; then
			argumentConflict=( "${argumentConflict[@]}" "-a, --aucdtect" )
		fi
	fi

	# If the array is not empty, the user called some incompatible options with
	# "-l, --all" or "-L, --reallyall", so print which options were called that
	# are incompatible and exit script
	if [[ -n "${argumentConflict[@]}" ]] ; then
		# "-l, --all"
		if [[ "${ALL}" == "true" ]] ; then
			printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " The below options conflict with \"-l, --all\""
		# "-L, --reallyall"
		elif [[ "${REALLYALL}" == "true" ]] ; then
			printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" " The below options conflict with \"-L, --reallyall\""
		fi

		# Iterate through array and print each value
		for i in "${argumentConflict[@]}" ; do
			printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
			" " "*" "     ${i}"
		done

		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " Please remove incompatible options."
		exit 1
	fi
fi

# If "-C, --compress-notest" and "-c, --compress" are both called, warn and exit
if [[ "${SKIP_TEST}" == "true" && "${COMPRESS_TEST}" == "true" ]] ; then
	printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
	" " "*" " Running both \"-c, --compress\" and \"-C, --compress-notest\" conflict!"
	printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
	" " "*" " Please choose one or the other."
	exit 1
fi

# If "-c, --compress" and "-t, --test" are both called, warn and exit
if [[ "${COMPRESS_TEST}" == "true" && "${TEST}" == "true" ]] ; then
	printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
	" " "*" " Running both \"-c, --compress\" and \"-t, --test\" conflict!"
	printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
	" " "*" " Please choose one or the other."
	exit 1
fi

# If "-a, --aucdtect" and "-A, --aucdtect-spectrogram" are both called, warn and exit
if [[ "${NO_SPECTROGRAM}" == "true"  && "${CREATE_SPECTROGRAM}" == "true" ]] ; then
	printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
	" " "*" " Running both \"-a, --aucdtect\" and \"-A, --aucdtect-spectrogram\" conflict!"
	printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
	" " "*" " Please choose one or the other."
	exit 1
fi

# Check if FLAC files exist
FIND_FLACS="$(find "${DIRECTORY}" -name "*.[Ff][Ll][Aa][Cc]" -print)"
if [[ -z "${FIND_FLACS}" ]] ; then
	no_flacs
	exit 1
fi

###########################
#  END PRE-SCRIPT CHECKS  #
###########################

##################
#  BEGIN SCRIPT  #
##################
# If "-l, --all" or "-L, --reallyall" was called,
# enable the various arguments to allow script to
# run them
if [[ "${ALL}" == "true" ]] ; then
	COMPRESS="true"
	MD5CHECK="true"
	PRUNE="true"
	REPLAYGAIN="true"
	REDO="true"
elif [[ "${REALLYALL}" == "true" ]] ; then
	COMPRESS="true"
	MD5CHECK="true"
	PRUNE="true"
	REPLAYGAIN="true"
	REDO="true"
	AUCDTECT="true"
	# This is needed to let script know that we want auCDtect
	# to create a spectrogram (ie "-A, --aucdtect-spectrogram)
	CREATE_SPECTROGRAM="true"
fi

# The below order is probably the best bet in ensuring time
# isn't wasted on doing unnecessary operations if the
# FLAC files are corrupt or have metadata issues
if [[ "${REDO}" == "true" ]] ; then
	# Display conflict warning and exit
	coverart_remove_conflict
fi

if [[ "${AUCDTECT}" == "true" ]] ; then
	# Check if auCDtect is found/installed
	if [[ -f "${AUCDTECT_COMMAND}" ]] ; then
		# If "-A, --aucdtect-spectrogram" was called
		# make sure SoX is installed before starting
		if [[ "${CREATE_SPECTROGRAM}" == "true" ]] ; then
			SOX_COMMAND="$(command -v sox)"
			if [[ -z "${SOX_COMMAND}" ]] ; then
				# SoX can't be found, exit
				printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
				" " "*" " It appears SoX is not installed. Please verify you"
				printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
				" " "*" " have this program installed and can be found in \$PATH"
				exit 1
			fi
		fi
		# Run auCDtect function/command
		aucdtect
	else
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " It appears auCDtect is not installed or you have not"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " configured this script to find it. Please verify you"
		printf "%s${BOLD_RED}%s${NORMAL}%s\n" \
		" " "*" " have this program installed."
		exit 1
	fi
fi

if [[ "${COMPRESS}" == "true" ]] ; then
	compress_flacs
fi

if [[ "${TEST}" == "true" ]] ; then
	test_flacs
fi

if [[ "${MD5CHECK}" == "true" ]] ; then
	md5_check
fi

if [[ "${REPLAYGAIN}" == "true" ]] ; then
	replaygain
fi

if [[ "${REDO}" == "true" ]] ; then
	redo_tags
fi

if [[ "${PRUNE}" == "true" ]] ; then
	prune_flacs
fi

# Display warning about legacy COVERART tag, if applicable
if [[ "${COVERART_WARNING}" == "true" ]] ; then
	printf ''
	coverart_warning
fi

exit 0
################
#  END SCRIPT  #
################
