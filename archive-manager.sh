#!/usr/bin/env bash

shopt -s nullglob

echowarn() { echo -e  "! $*"; }
echoabrt() { echo -e  "X $*"; exit 1; }
echoqstn() { echo -ne "? $*"; }
echoinfo() { echo -e  "> $*"; }
echoprog() { echo -e  "  $*"; }

archivetype=$(pwd)
archivetype=${archivetype: -3:3}
imgextnsn=png
vidextnsn=mp4
thmextnsn=webp

yellow="\e[32m"
white="\e[39m"

if [[ "$archivetype" == img ]]; then
	extension=$imgextnsn
	if [[ "$(convert 2>&1)" == *"convert command is deprecated in IMv7"* ]]; then
		convert="magick"
	else convert="convert"
	fi
	checkformat() { [[ $(file "$1") != *"PNG image data"* ]]; } # "JPEG XL"
	thmgen() { $convert "sto/$1.$extension" -quality 30 -resize 128x128 -strip "thm/$1.$thmextnsn" || echowarn "COULD NOT GENERATE THUMBNAIL"; }
elif [[ "$archivetype" == vid ]]; then
	extension=$vidextnsn
	checkformat() { [[ $(file "$1") != *"ISO Media, MP4"* ]]; }
	thmgen() { ffmpeg -i "sto/$1.$extension" -vf "thumbnail,scale='if(gt(iw,ih),128,-1)':'if(gt(iw,ih),-1,128)'" -frames:v 1 -q:v 5 "thm/$1.$thmextnsn" -loglevel 8 || echowarn "COULD NOT GENERATE THUMBNAIL"; }
else
	echoabrt "COULD NOT AUTO-DECIDE ARCHIVE TYPE (img/vid) BASED ON DIRECTORY LOCATION, MOVE THE ARCHIVE TO A DIRECTORY NAMED img/ OR vid/"
fi

thmdbgen() {
	checkcommand tar
	rm thm.tar.zst || echowarn "COULD NOT REMOVE OLD DATABASE"
	tar -cf thm.tar.zst thm --zstd || echowarn "COULD NOT CREATE NEW DATABASE"
	echoinfo "REFRESHED THUMBNAIL DATABASE $(du -h thm.tar.zst)"
}

checkcommand() {
	which "$1" 2>/dev/null 1>/dev/null || echoabrt "COMMAND $1 NOT FOUND"
	echoinfo "COMMAND $1 FOUND"
}

getitemname() { #extracts hash-tags from .../path/path/hash-tags.ext
	itemname=${1##*/}
	itemname=${itemname%%.*}
}

getitemtags() {
	itemtags=${1#*-}
	[[ "$1" == *-* ]] || itemtags=""
}

getitemhash() {
	itemhash=${1%%-*}
}

while :; do
	case "$1" in
		c | C | -c | -C )
			echoinfo "COMMITTING NEW ITEMS"
			checkcommand sha256sum
			checkcommand tar
			checkcommand file
			checkcommand ls
			[[ $archivetype == img ]] && checkcommand $convert
			if [[ "$(ls tmp/)" == "" ]]; then echoabrt "NO FILE TO COMMIT, tmp/ IS EMPTY"; fi
			declare -i c=0
			for fname in tmp/*; do
				tags=""
				if checkformat "$fname"; then # checkformat returns 1 (false) if correct, 0 (true) if not correct format
					if [[ $archivetype == vid ]]; then
						echowarn "$fname IS NOT IN mp4 FORMAT, SKIPPING, RE-MUX IT"
						continue
					elif [[ $archivetype == img ]]; then 
						echoprog "CONVERTING $fname to $extension"
						$convert "$fname" -strip "$fname.$extension" && rm "$fname" || echowarn "COULD NOT CONVERT FILE $fname TO $extension"
						fname="$fname.$extension"
					fi
				fi
				if [[ "${fname/#tmp\//}" == _* ]]; then
					tags=${fname#tmp\/_}
					tags=-${tags%%.*}
				fi
				read shasum _ <<< $(sha256sum "$fname")
				echoprog "MOVING $fname TO sto/$shasum$tags.$extension"
				mv "$fname" "sto/$shasum$tags.$extension" || echowarn "COULD NOT MOVE FILE"
				thmgen "$shasum$tags"
				c+=1
			done
			echoinfo "DONE COMMITTING $c ITEMS"
			thmdbgen
			break ;;

		r | R | -r | -R )
			if [[ -z "$2" ]]; then echoabrt "PROVIDE AN ITEM TO REMOVE"; fi
			getitemname "$2"
			echoinfo "REMOVING $itemname TO /tmp"
			mv "sto/$itemname.$extension" /tmp/ || echowarn "COULD NOT REMOVE FILE $2"
			rm "thm/$itemname.$thmextnsn" || echowarn "COULD NOT REMOVE FILE THUMBNAIL"
			break ;;

		PL | -itemlist )
			echoinfo "GENERATING ITEMLIST FOR PATCH"
			echoinfo "DO A SOFTCHECK BEFORE THIS"
			checkcommand /usr/bin/ls
			/usr/bin/ls sto/ > "archivepatchitemlist.$(whoami).$(date +%s).$extension.txt"
			echoinfo "ITEMLIST OF LOCAL ARCHIVE COPY CREATED: archivepatchitemlist.<epoch>.$extension.txt"
			echoinfo "SEND THE ITEMLIST TO REMOTE ARCHIVE OWNER, WHO MAY GENERATE A PATCH FOR YOU"
			break;;

		PS | -itempatch )
			echoinfo "READING ITEMLIST $2"
			echoinfo "DO A SOFTCHECK BEFORE THIS"
			if [[ ! -r "$2" ]]; then echoabrt "AN ITEMLIST FILE NOT PROVIDED OR NOT READABLE"; fi
			if [[ "$2" != *"archivepatchitemlist."*"$extension.txt" ]]; then echoabrt "PROVIDED ITEMLIST FILE IS OF WRONG TYPE"; fi
			checkcommand tar
			checkcommand wc
			declare -a stos=(sto/*)
			mapfile -t remotes <"$2"
			declare -a localtagspatch
			declare -a remoteitempatch
			declare -a tagconflict
			for fname in "${remotes[@]}"; do # check if local items are tagged by the remote copy
				getitemname "$fname"
				echoprog "CHECKING REMOTE ITEM $itemname"
				getitemhash "$itemname"
				getitemtags "$itemname"
				if [[ "${stos[*]}" != *"$itemname."* ]]; then
					if [[ "${stos[*]}" == *"$itemhash."* ]]; then
						echoprog "UNTAGGED LOCAL ITEM $itemhash WAS TAGGED ON REMOTE COPY WITH: $itemtags"
						localtagspatch+=("$itemname")
					elif [[ "${stos[*]}" == *"$itemhash-"* ]]; then
						if [[ -n "$itemtags" ]]; then
							tagconflict+=("$itemname")
							getitemname "sto/$itemhash"*
							echoprog "TAGGED LOCAL ITEM $itemname WAS TAGGED ON REMOTE COPY WITH: $itemtags; CONFLICTING, SKIPPING"
						else
							getitemname "sto/$itemhash"*
							echoprog "TAGGED LOCAL ITEM $itemname WAS NOT TAGGED ON REMOTE COPY, SKIPPING"
						fi
					else
						echoprog "LOCAL COPY DOES NOT HAVE THE REMOTE ITEM $itemname; SKIPPING"
					fi
				fi
			done
			echoinfo "DONE CHECKING REMOTE ITEMS"
			for fname in "${stos[@]}"; do # check if remote copy have local items
				getitemname "$fname"
				getitemhash "$itemname"
				echoprog "CHECKING IF REMOTE COPY HAS LOCAL ITEM $itemname"
				if [[ "${remotes[*]}" != *"$itemhash"* ]]; then
					echoprog "REMOTE COPY DOES NOT HAVE LOCAL ITEM: $itemname"
					remoteitempatch+=("$itemname")
				fi
			done
			echoinfo "DONE CHECKING LOCAL ITEMS"
			if [[ -n "$localtagspatch" ]]; then
				echoqstn "APPLY ${#localtagspatch[@]}-MANY REMOTE TAGGINGS TO LOCAL COPY (y/n)? "
					read answer
					if [[ "$answer" == "y" ]]; then
						for itemname in "${localtagspatch[@]}"; do
							getitemhash "$itemname"
							getitemtags "$itemname"
							echoprog "TAGGING LOCAL ITEM: $itemhash WITH: $itemtags"
							mv "sto/$itemhash.$extension" "sto/$itemhash-$itemtags".$extension || echowarn "COULD NOT TAG FILE"
							mv "thm/$itemhash.$thmextnsn" "thm/$itemhash-$itemtags".$thmextnsn || echowarn "COULD NOT TAG FILE"
						done
					fi
			fi
			if [[ -n "$remoteitempatch" ]]; then
				echoqstn "GENERATE PATCH WITH ${#remoteitempatch[@]}-MANY ITEMS FOR REMOTE COPY (y/n)? "
					read answer
					if [[ "$answer" == "y" ]]; then
						checkcommand tar
						checkcommand date
						checkcommand whoami
						mkdir /tmp/ArchivePatch
						for itemname in "${remoteitempatch[@]}"; do
							getitemhash "$itemname"
							getitemtags "$itemname"
							echoprog "ADDING LOCAL ITEM $itemname TO PATCHLOAD"
							if [[ "${#itemname}" -gt 64 ]]; then
								cp "sto/$itemname.$extension" /tmp/ArchivePatch/_"$itemtags.$itemhash.$extension"
							else
								cp "sto/$itemname.$extension" /tmp/ArchivePatch/
							fi
						done
						tar -cf "archivepatchload.$(whoami).$(date +%s).$extension.tar" -C /tmp/ArchivePatch/ .
						rm -r /tmp/ArchivePatch/ #cleanup
						echoinfo "PATCHLOAD FOR REMOTE ARCHIVE COPY PRODUCED: archivepatchload.<epoch>.$extension.tar"
						echoinfo "THE PATCHLOAD CONTAINS NEW ITEMS WITH CORRECT TAGS, IT CAN BE EXTRACTED ON tmp/ OF THE REMOTE ARCHIVE COPY"
						echoinfo "SEND THIS PATCH TO THE OWNER OF THE REMOTE ARCHIVE COPY"
					fi
					echoqstn "REMOVE ${#remoteitempatch[@]}-MANY LOCAL ITEMS THAT ARE NOT IN THE REMOTE COPY (y/n)? "
						read answer
						if [[ "$answer" == "y" ]]; then
							for itemname in "${remoteitempatch[@]}"; do
								echoprog "REMOVING $itemname TO /tmp"
								mv "sto/$itemname.$extension" /tmp/ || echowarn "COULD NOT REMOVE FILE $2"
								rm "thm/$itemname.$thmextnsn" || echowarn "COULD NOT REMOVE FILE THUMBNAIL"
							done
							echostat "DONE REMOVING ITEMS TO /tmp"
						fi
			fi
			if [[ -n "$tagconflict" ]]; then
				echoinfo "TAG CONFLICTS: ${tagconflict[*]}"
				echoqstn "MANUALLY RESOLVE ${#tagconflict[@]}-MANY TAGGING DIFFERENCES ON LOCAL COPY ONE-BY-ONE (y/n)? "
					read answer
					if [[ "$answer" == "y" ]]; then
						for ritemname in "${tagconflict[@]}"; do
							getitemhash "$ritemname"
							getitemtags "$ritemname"
							ritemtags="$itemtags"
							getitemname "sto/$itemhash"*
							if [[ "$itemname" == "sto/$itemhash"* ]]; then
								echowarn "CANNOT FIND THE CONFLICTING ITEM IN LOCAL ARCHIVE, FIX THIS MANUALLY, SKIPPING"
								continue
							fi
							getitemtags "$itemname"
							echoinfo "LOCAL TAGS: $itemtags; REMOTE TAGS: $ritemtags"
							echoqstn "WHICH TAGS SHOULD LOCAL ITEM HAVE (r[emote]/l[ocal]/c[hange manually])? "
							read answer
							if [[ "$answer" == "r" ]]; then
								echoprog "TAGGING LOCAL ITEM: $itemname WITH: $ritemtags"
								mv "sto/$itemname.$extension" "sto/$itemhash-$ritemtags.$extension" || echowarn "COULD NOT TAG FILE"
								mv "thm/$itemname.$thmextnsn" "thm/$itemhash-$ritemtags.$thmextnsn" || echowarn "COULD NOT TAG FILE"
							elif [[ "$answer" == "c" ]]; then
								echoqstn "ENTER NEW TAGS (LEAVE EMPTY FOR NO TAGS)?"
								read nitemtags
								echoprog "TAGGING LOCAL ITEM: $itemname WITH: $nitemtags"
								mv "sto/$itemname.$extension" "sto/$itemhash-$nitemtags.$extension" || echowarn "COULD NOT TAG FILE"
								mv "thm/$itemname.$thmextnsn" "thm/$itemhash-$nitemtags.$thmextnsn" || echowarn "COULD NOT TAG FILE"
							else
								echoprog "KEEPING LOCAL TAGS"
							fi
						done
					fi
			fi
			break;;

		-softcheck )
			echoinfo "SOFTCHECK"
			declare -a thms=(thm/*)
			declare -a stos=(sto/*)
			declare -a missingthms
			declare -a badtagthms
			declare -a orphanthms
			for fname in sto/*; do
				getitemname "$fname"
				echoprog "CHECKING THM OF ITEM: $itemname"
				if [[ "${thms[*]}" != *"$itemname."* ]]; then
					getitemhash "$itemname"
					if [[ "${thms[*]}" == *"$itemhash"* ]]; then
						echoinfo "THUMBNAIL NOT TAGGED PROPERLY FOR ITEM: $itemname"
						badtagthms+=("$itemname")
					else
						echoinfo "MISSING THUMBNAIL FOR ITEM: $itemname"
						missingthms+=("$itemname")
					fi
				fi
			done
			echoinfo "DONE CHECKING THUMBNAILS OF ITEMS"
			if [[ -n "$missingthms" ]]; then
				echoinfo "MISSING THUMBNAIL ITEMS: ${missingthms[*]}"
				echoqstn "GENERATE MISSING THMS FOR ${#missingthms[@]}-MANY ITEMS (y/n)? "
					read answer
					if [[ "$answer" == "y" ]]; then
						[[ $archivetype == vid ]] && checkcommand ffmpeg
						[[ $archivetype == img ]] && checkcommand $convert
						for itemname in "${missingthms[@]}"; do
							echoprog "GENERATING THUMBNAIL FOR ITEM: $itemname"
							thmgen "$itemname"
						done
					fi
			fi
			if [[ -n "$badtagthms" ]]; then
				echoinfo "TAG MISMATCH ITEMS: ${badtagthms[*]}"
				echoqstn "FIX TAGGING MISMATCHES FOR ${#badtagthms[@]}-MANY THMS (y/n)? "
					read answer
					if [[ "$answer" == "y" ]]; then
						for itemname in "${badtagthms[@]}"; do
							getitemname "thm/$itemname"*
							oldname=$itemname
							getitemhash "$itemname"
							getitemname "sto/$itemhash"*
							newname=$itemname
							echoprog "RENAMING THUMBNAIL $oldname TO $itemname"
							mv "thm/$oldname.$thmextnsn" "thm/$newname.$thmextnsn" || echowarn "COULD NOT MOVE FILE"
						done
					fi
			fi
			for fname in thm/*; do
				getitemname "$fname"
				echoprog "CHECKING THUMBNAIL $itemname"
				if [[ "${stos[*]}" != *"$itemname."* ]]; then
					echoinfo "ORPHAN THUMBNAIL FOUND: $itemname";
					orphanthms+=("$itemname")
				fi
			done
			echoinfo "DONE CHECKING ITEMS OF THUMBNAILS"
			if [[ -n "$orphanthms" ]]; then
				echoinfo "ORPHAN THUMBNAILS: ${orphanthms[*]}"
				echoqstn "REMOVE ${#orphanthms[@]}-MANY ORPHAN THMS (y/n)? "
					read answer
					if [[ "$answer" == "y" ]]; then
						for itemname in "${orphanthms[@]}"; do
							rm "thm/$itemname.$thmextnsn" || echowarn "COULD NOT REMOVE FILE"
						done
					fi
			fi
			if [[ -z "$missingthms" && -z "$badtagthms" && -z "$orphanthms" ]] then
				echoinfo "ALL FILES ARE GOOD"
			fi
			break ;;

		-hardcheck )
			echoqstn "CHECKING THE HASHES OF ALL ITEMS MAY TAKE A VERY LONG TIME, ARE YOU SURE (y/n)? "
			read answer
			if [[ "$answer" == "y" ]]; then
				echoinfo "HARDCHECK"
				checkcommand sha256sum
				declare -a corruptitems
				for fname in sto/*; do
					read shasum _ <<< $(sha256sum "$fname")
					echoprog "CHECKING $fname $shasum"
					getitemname "$fname"
					getitemhash "$itemname"
					if [[ "$itemhash" != "$shasum" ]]; then
						echoprog "CORRUPT ITEM FOUND: $itemname"
						corruptitems+=("$itemname")
					fi
				done
				echoprog "DONE CHECKING ITEMS"

				if [[ -n "$corruptitems" ]] then
					echoinfo "FOUND CORRUPT ITEMS: ${corruptitems[*]}"
				else
					echoinfo "ALL FILES ARE GOOD"
				fi
			fi
			break ;;

		g | G | -g | -G )
			if [[ -z "$2" ]] || [[ -z "$3" ]]; then echoabrt "PROVIDE AN ITEM AND TAG(S) "; fi
			tags=${3// /-}
			echoprog "TAGGING $2 WITH $tags"
			getitemname "$2"
			mv "sto/$itemname.$extension" "sto/$itemname-$tags.$extension" || echowarn "COULD NOT TAG FILE"
			mv "thm/$itemname.$thmextnsn" "thm/$itemname-$tags.$thmextnsn" || echowarn "COULD NOT TAG FILE"
			break ;;

		u | U | -u | -U )
			if [[ -z "$2" ]]; then echoabrt "PROVIDE AN ITEM "; fi
			echoprog "REMOVING ALL TAGS FROM ITEM: $2"
			getitemname "$2"
			getitemhash "$itemname"
			mv "sto/$itemname.$extension" "sto/$itemhash.$extension" || echowarn "COULD NOT UNTAG FILE"
			mv "thm/$itemname.$thmextnsn" "thm/$itemhash.$thmextnsn" || echowarn "COULD NOT UNTAG FILE"
			break ;;

		-thumbnailgen )
			echoqstn "REGENERATING ALL THUMBNAILS FOR ALL ITEMS MAY TAKE A VERY LONG TIME, ARE YOU SURE (y/n)? "
			read answer
			if [[ "$answer" == "y" ]]; then
				echoinfo "REGENERATING ALL THUMBNAILS"
				checkcommand tar
				[[ $archivetype == vid ]] && checkcommand ffmpeg
				[[ $archivetype == img ]] && checkcommand $convert
				rm thm/*
				declare -i c=0
				for fname in sto/*; do
					getitemname "$fname"
					thmgen "$itemname"
					echoprog "GENERATING THM FOR ITEM: $itemname"
					c+=1
				done
				echoinfo "REGENERATED THMS FOR $c-MANY ITEMS ITEMS"
				thmdbgen
			fi
			break ;;

		f | F | -f | -F )
			echoinfo "REGENERATING thm.tar.zst"
			thmdbgen
			break ;;

		w | W | -w | -W )
			echoinfo "STARTING A PYTHON WEB SERVER"
			echoinfo "CTRL-C TO CLOSE IT"
			checkcommand python
			python -m http.server
			break ;;

		*)
			echoinfo "Archive manager v3.4.1"
			echoinfo "Use"	$yellow	"C"			$white	      "to commit new items"
			echoinfo "Use"	$yellow	"R <item>"		$white	      "to remove an item"
			echoinfo "Use"	$yellow	"PL"			$white	      "to generate local item list"
			echoinfo "Use"	$yellow	"PS <itemlist>"		$white	      "to tag local items or make patch for remote archive copy"
			echoinfo "Use"	$yellow	"-softcheck"		$white	      "to check thumbnails filenames"
			echoinfo "Use"	$yellow	"-hardcheck"		$white	      "to check item hashes"
			echoinfo "Use"	$yellow	"-thumbnailgen"		$white	      "to regenerate all thumbnails"
			echoinfo "Use"	$yellow	"G <item> <tag>"	$white	      "to tag an item"
			echoinfo "Use"	$yellow	"U"			$white	      "to untag an item"
			echoinfo "Use"	$yellow	"F"			$white	      "to regenerate thm.tar.zst"
			echoinfo "Use"	$yellow	"W"			$white	      "to start a web server"
			break ;;
	esac
done

