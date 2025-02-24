#!/bin/bash

read extension _ <<< $(/bin/ls sto/);
declare extension=${extension#*.}
if [[ "$extension" != png ]] && [[ "$extension" != mp4 ]]; then
	echo "! COULD NOT AUTO-DECIDE ARCHIVE TYPE (img/vid)"
	echo -n "? WHAT SHOULD THE ITEM FILE EXTENSION BE (png/mp4)? "
	read extension
	echo "USING ITEM EXTENSION: '$extension'"
fi

[[ "$extension" == png ]] && [[ -n $(convert 2>&1 | grep "convert command is deprecated in IMv7") ]] && declare convert="magick" || declare convert="convert"

if [ -v $DEBUG ]; then declare linestart="\e[2K\r"; else declare linestart=""; fi

thmgen() {
	if [ $extension == "mp4" ]; then
		ffmpeg -i "sto/$1.$extension" -vf "thumbnail,scale='if(gt(iw,ih),128,-1)':'if(gt(iw,ih),-1,128)'" -frames:v 1 -q:v 5 "thm/$1.jpg" -loglevel 8 || echo "! COULD NOT GENERATE THUMBNAIL"
	elif [ $extension == "png" ]; then
		$convert "sto/$1.$extension" -quality 50 -resize 128x128 "thm/$1.jpg" || echo "! COULD NOT GENERATE THUMBNAIL"
	fi
}

thmdbgen() {
	checkcommand tar
	rm thm.tar.zst || echo "! COULD NOT REMOVE OLD DATABASE"
	tar -cf thm.tar.zst thm --zstd || echo "! COULD NOT CREATE NEW DATABASE"
	echo "> REFRESHED THUMBNAIL DATABASE ($(du -h thm.tar.zst | (read n _; echo -n $n)))"
}

checkcommand() {
	command=$(which "$1" 2>/dev/null)
	if [ ! "$command" ] || [ "$command" = '' ]; then
		echo "! COULD NOT FIND COMMAND: $1"
		exit 1
	fi
	echo "> FOUND COMMAND $1"
}

checkformat() { # return 1 if correct, 0 if not correct format
	[ $extension == "mp4" ] && [ -z "$(ffprobe $1 2>&1 | grep 'Video: h264')" ]
	[ $extension == "png" ] && [ $(identify -format "%m" "$1") != "PNG" ]
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
		-S | --sync)
			echo "> SYNCING NEW ITEMS"
			checkcommand sha256sum
			checkcommand tar
			[ $extension == "mp4" ] && checkcommand ffmpeg
			[ $extension == "png" ] && checkcommand $convert
			[ $extension == "png" ] && checkcommand identify
			if [ "$(ls tmp/)" == "" ]; then echo "! NO FILE TO SYNC, tmp/ EMPTY"; break; fi
			declare -i c=0
			for fname in tmp/*; do
				tags=""
				if checkformat $fname; then
					if [ $extension == "mp4" ]; then
						echo "! FILE NOT USING H264 CODEC, SKIPPING $fname, PLEASE RE-ENCODE IT"
						continue
					elif [ $extension == "png" ]; then 
						echo " CONVERTING $fname to PNG"
						$convert "$fname" "$fname".$extension && rm "$fname" || echo "! COULD NOT CONVERT FILE $fname TO PNG"
						fname="$fname".$extension
					fi
				fi
				if [[ ${fname/#tmp\//} == _* ]]; then
					tags=${fname#tmp\/_}
					tags=-${tags%%.*}
				fi
				read shasum _ <<< $(sha256sum "$fname")
				echo " MOVING $fname TO sto/$shasum$tags.$extension"
				mv "$fname" "sto/$shasum$tags.$extension" || echo "! COULD NOT MOVE FILE"
				thmgen $shasum$tags
				c+=1
			done
			echo -e "$linestart DONE SYNCING ITEMS"
			echo "> SYNCED $c ITEMS"
			thmdbgen
			break ;;

		-R | --remove)
			if [[ -z "$2" ]]; then echo "! PROVIDE AN ITEM TO REMOVE "; exit 1; fi
			getitemname $2
			echo "> REMOVING $itemname TO /tmp"
			mv sto/$itemname.$extension /tmp/ || echo "! COULD NOT REMOVE FILE $2"
			rm thm/$itemname.jpg || echo "! COULD NOT REMOVE FILE THUMBNAIL"
			break ;;

		-PL | --itemlist)
			echo "> GENERATING ITEMLIST FOR PATCH"
			echo "> DO A SOFTCHECK BEFORE THIS"
			/bin/ls sto/ > "archivepatchitemlist.$(whoami).$(date +%s).$extension.txt"
			echo "> ITEMLIST OF LOCAL ARCHIVE COPY CREATED: archivepatchitemlist.<epoch>.$extension.txt"
			echo "> SEND THE ITEMLIST TO REMOTE ARCHIVE OWNER, WHO MAY GENERATE A PATCH FOR YOU"
			break;;

		-PS | --itempatch)
			echo "> READING ITEMLIST $2"
			echo "> DO A SOFTCHECK BEFORE THIS"
			if [[ -z "$2" ]]; then echo "! PROVIDE AN itemlist FILE "; exit 1; fi
			if [[ "$2" != *"archivepatchitemlist."*"$extension.txt" ]]; then echo "! ITEMLIST FILE NAME BAD, ZORT"; exit 1; fi
			checkcommand tar
			checkcommand wc
			stos=$(/bin/ls sto/)
			remote=$(cat "$2")
			localtagspatch=""
			remoteitempatch=""
			tagconflict=""
			for fname in $remote; do # check if local items are tagged by the remote copy
				getitemname $fname
				echo -ne "$linestart CHECKING REMOTE ITEM $itemname"
				getitemhash $itemname
				getitemtags $itemname
				if [[ "$stos" != *"$itemname."* ]]; then
					if [[ "$stos" == *"$itemhash."* ]]; then
						echo -e "$linestart UNTAGGED LOCAL ITEM $itemhash WAS TAGGED ON REMOTE COPY WITH: $itemtags"
						localtagspatch="$localtagspatch $itemname"
					elif [[ "$stos" == *"$itemhash-"* ]]; then
						if [[ -n $itemtags ]]; then
							tagconflict="$tagconflict $itemname"
							getitemname sto/$itemhash*
							echo -e "$linestart TAGGED LOCAL ITEM $itemname WAS TAGGED ON REMOTE COPY WITH: $itemtags; CONFLICTING, SKIPPING"
						else
							getitemname sto/$itemhash*
							echo -e "$linestart TAGGED LOCAL ITEM $itemname WAS NOT TAGGED ON REMOTE COPY, SKIPPING"
						fi
					else
						echo -e "$linestart LOCAL COPY DONT HAVE REMOTE ITEM $itemname; SKIPPING"
					fi
				fi
			done
			echo -e "$linestart DONE CHECKING REMOTE ITEMS"
			for fname in $stos; do # check if remote copy have local items
				getitemname $fname
				getitemhash $itemname
				echo -ne "$linestart CHECKING IF REMOTE COPY HAS LOCAL ITEM $itemname"
				if [[ "$remote" != *"$itemhash"* ]]; then
					echo -e "$linestart REMOTE COPY DOESNT HAVE LOCAL ITEM: $itemname"
					remoteitempatch="$remoteitempatch $itemname"
				fi
			done
			echo -e "$linestart DONE CHECKING LOCAL ITEMS"
			if [[ "$localtagspatch" ]]; then
				echo -n "? APPLY $(echo $localtagspatch | wc -w)-MANY REMOTE TAGGINGS TO LOCAL COPY (y/n)? "
				read answer
				if [[ $answer == "y" ]]; then
					for itemname in $localtagspatch; do
						getitemhash $itemname
						getitemtags $itemname
						echo " TAGGING LOCAL ITEM: $itemhash WITH: $itemtags"
						mv sto/$itemhash.$extension sto/$itemhash-$itemtags.$extension || echo "! COULD NOT TAG FILE"
						mv thm/$itemhash.jpg thm/$itemhash-$itemtags.jpg || echo "! COULD NOT TAG FILE"
					done
				fi
			fi
			if [[ "$remoteitempatch" ]]; then
				echo -n "? GENERATE PATCH WITH $(echo $remoteitempatch | wc -w)-MANY ITEMS FOR REMOTE COPY (y/n)? "
				read answer
				if [[ $answer == "y" ]]; then
					mkdir /tmp/ArchivePatch
					for itemname in $remoteitempatch; do
						getitemhash $itemname
						getitemtags $itemname
						echo " ADDING LOCAL ITEM $itemname TO PATCHLOAD"
						if [[ ${#name} -gt 64 ]]; then
							cp sto/$itemname.$extension /tmp/ArchivePatch/_$itemtags.$itemhash.$extension
						else
							cp sto/$itemname.$extension /tmp/ArchivePatch/
						fi
					done
					tar -cf "archivepatchload.$(whoami).$(date +%s).$extension.tar" -C /tmp/ArchivePatch/ .
					rm -r /tmp/ArchivePatch/ #cleanup
					echo "> PATCHLOAD FOR REMOTE ARCHIVE COPY PRODUCED: archivepatchload.<epoch>.$extension.tar"
					echo "> THE PATCHLOAD CONTAINS NEW ITEMS WITH CORRECT TAGS, IT CAN BE EXTRACTED ON tmp/ OF THE REMOTE ARCHIVE COPY"
					echo "> SEND THIS PATCH TO THE OWNER OF THE REMOTE ARCHIVE COPY"
				fi
				echo -n "? REMOVE $(echo $remoteitempatch | wc -w)-MANY LOCAL ITEMS THAT ARE NOT IN THE REMOTE COPY (y/n)? "
				read answer
				if [[ $answer == "y" ]]; then
					for itemname in $remoteitempatch; do
						echo " REMOVING $itemname TO /tmp"
						mv sto/$itemname.$extension /tmp/ || echo "! COULD NOT REMOVE FILE $2"
						rm thm/$itemname.jpg || echo "! COULD NOT REMOVE FILE THUMBNAIL"
					done
					echo "$linestart DONE REMOVING ITEMS TO /tmp"
				fi
			fi
			if [[ "$tagconflict" ]]; then
				echo $tagconflict
				echo -n "? MANUALLY RESOLVE $(echo $tagconflict | wc -w)-MANY TAGGING DIFFERENCES ON LOCAL COPY (y/n)? "
				read answer
				if [[ $answer == "y" ]]; then
					for ritemname in $tagconflict; do
						getitemhash $ritemname
						getitemtags $ritemname
						ritemtags="$itemtags"
						getitemname sto/$itemhash*
						if [[ $itemname == "sto/$itemhash*" ]]; then
							echo "! CANNOT FIND THE CONFLICTING ITEM IN LOCAL ARCHIVE, FIX THIS MALUALLY, SKIPPING"
							continue
						fi
						getitemtags $itemname
						echo " LOCAL TAGS: $itemtags; REMOTE TAGS: $ritemtags"
						echo -n "? WHAT TO DO (r[emote]/l[ocal]/c[hange])? "
						read answer
						if [[ $answer == "r" ]]; then
							echo " TAGGING LOCAL ITEM: $itemname WITH: $ritemtags"
							mv sto/$itemname.$extension sto/$itemhash-$ritemtags.$extension || echo "! COULD NOT TAG FILE"
							mv thm/$itemname.jpg thm/$itemhash-$ritemtags.jpg || echo "! COULD NOT TAG FILE"
						elif [[ $answer == "c" ]]; then
							echo -n "? ENTER NEW TAGS (LEAVE EMPTY FOR NO TAGS)?"
							read nitemtags
							echo " TAGGING LOCAL ITEM: $itemname WITH: $nitemtags"
							mv sto/$itemname.$extension sto/$itemhash-$nitemtags.$extension || echo "! COULD NOT TAG FILE"
							mv thm/$itemname.jpg thm/$itemhash-$nitemtags.jpg || echo "! COULD NOT TAG FILE"
						else
							echo " KEEPING LOCAL TAGS"
						fi
					done
				fi
			fi
			break;;

		-SC | --softcheck)
			echo "> SOFTCHECK"
			thms=$(/bin/ls thm/)
			stos=$(/bin/ls sto/)
			missingthms=""
			badtagthms=""
			orphanthms=""
			for fname in sto/*; do
				getitemname $fname
				echo -ne "$linestart CHECKING THM OF ITEM: $itemname"
				if [[ "$thms" != *"$itemname."* ]]; then
					getitemhash $item
					if [[ "$thms" == *"itemhash"* ]]; then
						echo -e "$linestart THUMBNAIL NOT TAGGED PROPERLY FOR ITEM: $itemname"
						badtagthms="$badtagthms $itemname"
					else
						echo -e "$linestart MISSING THUMBNAIL FOR ITEM: $itemname"
						missingthms="$missingthms $itemname"
					fi
				fi
			done
			echo -e "$linestart DONE CHECKING THMS"
			for fname in thm/*; do
				getitemname $fname
				echo -ne "$linestart CHECKING $itemname"
				if [[ "$stos" != *"$itemname."* ]]; then
					echo -e "$linestart ORPHAN THUMBNAIL FOUND: $itemname";
					orphanthms="$orphanthms $itemname"
				fi
			done
			echo -e "$linestart DONE CHECKING ITEMS"
			if [[ "$missingthms" ]]; then
				echo -n "? GENERATE MISSING THMS FOR $(echo $missingthms | wc -w)-MANY ITEMS (y/n)? "
				read answer
				if [[ $answer == "y" ]]; then
					[ $extension == "mp4" ] && checkcommand ffmpeg
					[ $extension == "png" ] && checkcommand $convert
					for itemname in $missingthms; do
						echo " GENERATING THM FOR ITEM: $itemname"
						thmgen $itemname
					done
				fi
			fi
			if [[ "$badtagthms" ]]; then
				echo -n "? FIX TAGING MISMATCHES FOR $(echo $badtagthms | wc -w)-MANY THMS (y/n)? "
				read answer
				if [[ $answer == "y" ]]; then
					for itemname in $badtagthms; do
						getitemname thm/$itemname*
						oldname=$itemname
						getitemhash $itemname
						getitemname sto/$itemhash*
						newname=$itemname
						echo " RETAGGING THM: $oldname AS: $itemname"
						mv "thm/$oldname.jpg" "thm/$newname.jpg" || echo "! COULD NOT MOVE FILE"
					done
				fi
			fi
			if [[ "$orphanthms" ]]; then
				echo -n "? REMOVE $(echo $orphanthms | wc -w)-MANY ORPHAN THMS (y/n)? "
				read answer
				if [[ $answer == "y" ]]; then
					for itemname in $orphanthms; do
						rm thm/$itemname.jpg || echo "! COULD NOT REMOVE FILE"
					done
				fi
			fi
			break ;;

		-HC | --hardcheck)
			echo -n "? CHECHING THE HASHES OF ALL ITEMS MAY TAKE A VERY LONG TIME, ARE YOU SURE (y/n)? "
			read answer
			if [[ $answer == "y" ]]; then
				echo "> HARDCHECK"
				checkcommand sha256sum
				for fname in sto/*; do
					read shasum _ <<< $(sha256sum $fname)
					echo -ne "$linestart CHECKING $fname $shasum"
					getitemname $fname
					getitemhash $itemname
					if [[ $itemhash != $shasum ]]; then
						echo -e "$linestart CORRUPT ITEM FOUND: $itemname"
					fi
				done
				echo -e "$linestart DONE CHECKING ITEMS"
			fi
			break ;;

		-G | --tag)
			if [[ -z "$2" ]] || [[ -z "$3" ]]; then echo "! PROVIDE AN ITEM AND TAG(S) "; exit 1; fi
			tags=${3// /-}
			echo " TAGGING $2 WITH $tags"
			getitemname $2
			mv sto/$itemname.$extension sto/$itemname-$tags.$extension || echo "! COULD NOT TAG FILE"
			mv thm/$itemname.jpg thm/$itemname-$tags.jpg || echo "! COULD NOT TAG FILE"
			break ;;

		-U | --untag)
			if [[ -z "$2" ]]; then echo "! PROVIDE AN ITEM "; exit 1; fi
			echo " REMOVING ALL TAGS FROM ITEM: $2"
			getitemname $2
			getitemhash $itemname
			mv sto/$itemname.$extension sto/$itemhash.$extension || echo "! COULD NOT UNTAG FILE"
			mv thm/$itemname.jpg thm/$itemhash.jpg || echo "! COULD NOT UNTAG FILE"
			break ;;

		-T | --thumbnailgen)
			echo -n "? REGENERATING ALL THUMBNAILS FOR ALL ITEMS MAY TAKE A VERY LONG TIME, ARE YOU SURE (y/n)? "
			read answer
			if [[ $answer == "y" ]]; then
				echo "> REGENERATING ALL THUMBNAILS"
				checkcommand tar
				[ $extension == "mp4" ] && checkcommand ffmpeg
				[ $extension == "png" ] && checkcommand $convert
				rm thm/*
				declare -i c=0
				for fname in sto/*; do
					getitemname $fname
					thmgen $itemname
					echo -ne "$linestart GENERATING THM FOR ITEM: $itemname"
					c+=1
				done
				echo -e "$linestart REGENERATED THMS FOR $c-MANY ITEMS ITEMS"
				thmdbgen
			fi
			break ;;

		-F | --refresh)
			echo "> REGENERATING thm.tar.zst"
			thmdbgen
			break ;;

		*)
			echo "    Archive manager v3.2.3"
			echo "Use -S to sync new items"
			echo "Use -R to remove items"
			echo "Use -PL to generate local item list"
			echo "Use -PS <itemlist> to parse remote item list, tag local items, make patch for remote archive copy"
			echo "Use -SC to softcheck, check thumbnails"
			echo "Use -HC to hardcheck, check item hashes"
			echo "Use -T to regenerate all thumbnails"
			echo "Use -G <item> <tag> to tag an item"
			echo "Use -U to untag an item"
			echo "Use -F to regenarate thm.tar.zst"
			break ;;
	esac
done

