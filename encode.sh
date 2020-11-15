#!/bin/sh

set -e

OUT_DIR=out

crop() {
    local video_file=${1}
    mplayer $video_file -vf cropdetect -vo null -ss 5:00 -frames 100 2>/dev/null\
	| tail -n5 \
	| sed -ne 's/^.*crop=\([0-9]\+:[0-9]\+:[0-9]\+:[0-9]\+\)).*$/\1/p'
}

video_track_id() {
    local mkv=${1}
    mkvinfo $mkv | grep -e 'Track type: video' -B2 \
	| sed -ne 's/^.*mkvextract: \([0-9]\+\).*$/\1/p'
}

audio_tracks() {
    local mkv=${1}
    mkvinfo $mkv | grep -e 'Track type: audio' -A8 -B2 \
	| tr -d '\n' \
	| sed -e 's/--/\n/' \
	| sed -ne 's/^.*mkvextract: \([0-9]\+\).*Language: \([a-z]\{3\}\).*Name: \([a-zA-Z]\+\).*$/\1,\2,\3/p'
}

dump_wav() {
    local audio_file=${1}
    local wav_file=${2}
    
    mplayer $audio_file -vc dummy -vo null -ao "pcm:file=$wav_file" 
}

make_ogg() {
    local audio_file=${1}
    local out=$(dirname $audio_file)
    local wav_file=$out/$(basename -s audio.to_ogg $audio_file)wav

    dump_wav $audio_file $wav_file
    oggenc -q5 $wav_file
}

subtitle_tracks() {
    local mkv=${1}
    mkvinfo $mkv  | grep -e 'Track type: subtitles' -A4 -B2 \
    	| tr -d '\n' \
    	| sed -e 's/--/\n/' \
    	| sed -ne 's/^.*mkvextract: \([0-9]\+\).*Language: \([a-z]\{3\}\).*$/\1,\2/p'
}

extract() {
    mkv=${1}
    out=${2}
    video_track_id=$(video_track_id $mkv)
    track_opts="$video_track_id:$out/$video_track_id.video"

    for track in $(audio_tracks $mkv); do
	local id=$(echo "$track" | cut -d ',' -f1)
	local lang=$(echo "$track" | cut -d ',' -f2)
	local type=$(echo "$track" | cut -d ',' -f3)
	
	if [ $type = 'Stereo' ]; then
	    track_opts="$track_opts $id:$out/$lang.$id.audio.to_ogg"
	else
	    track_opts="$track_opts $id:$out/$lang.$id.audio"
	fi
    done
    
    for track in $(subtitle_tracks $mkv); do
	id=$(echo "$track" | cut -d ',' -f1)
	lang=$(echo "$track" | cut -d ',' -f2)

	track_opts="$track_opts $id:$out/$lang.$id.subtitle"
    done

    mkvextract $mkv tracks $track_opts
}



encode_video() {
    local src=${1}
    local out=$(dirname $src)
    local dst_file=$out/$(basename -s video $src)x264
    local bitrate=1000
    local filter_crop="crop=${2}"
    # low
    # local quality="subq=5:partitions=all:8x8dct:me=umh:frameref=3:bframes=4:b_pyramid=normal:weight_b:bitrate=$bitrate"
    # local passes=1
    # high
    local passes="1 2"
    
    for pass in $passes; do
	quality="subq=7:partitions=all:8x8dct:me=umh:frameref=12:bframes=4:b_pyramid=normal:weight_b:pass=$pass:bitrate=$bitrate"
	mencoder $src -aspect 16/9 -vf $filter_crop -mc 0 \
		      -ovc x264 -x264encopts \
		      $quality \
		      -oac copy -of rawvideo -o $dst_file \
		      -nosub
    done
}

make_mkv() {
    local wdir=${1}
    local track_opts=""

    for f in $(find $wdir -name '*.audio'); do
	lang=$(echo $(basename $f) | cut -d '.' -f1)
	track_opts="$track_opts --language 0:$lang $f"
    done

    for f in $(find $wdir -name '*.ogg'); do
	lang=$(echo $(basename $f) | cut -d '.' -f1)
	track_opts="$track_opts --language 0:$lang $f"
    done

    for f in $(find $wdir -name '*.idx'); do
	lang=$(echo $(basename $f) | cut -d '.' -f1)
	track_opts="$track_opts --language 0:$lang --default-track 0:false -s -0 $f"
    done

    local mkv=$(dirname $wdir)/$(basename $wdir).mkv
    test -f $mkv && rm $mkv
    mkvmerge -o $mkv $wdir/0.x264 $track_opts
}


encode() {
    local out=${1}
    
    for f in $(find $out -name '*.audio.to_ogg'); do
	make_ogg $f
    done

    for f in $out/*.video; do
	encode_video $f $(crop $f)
    done
}

make_mkvs() {
    for wdir in $OUT_DIR/*; do
	make_mkv $wdir
    done 
}

#dump_audio
#dump_subtitles
extract_tracks() {
    local src=${1}

    test -d $OUT_DIR && rm -rf $OUT_DIR
    mkdir $OUT_DIR

    for mkv in $(dirname $src)/$(basename $src)/*.mkv; do
	local wdir=$OUT_DIR/$(basename -s .mkv $mkv)
	mkdir $wdir
	extract $mkv $wdir
    done
}

encode_files() {
    local crop=${1}

    for wdir in $OUT_DIR/*; do
	encode $wdir
    done
}

while getopts c:em opt; do
    case $opt in
	c) SRC_DIR=$OPTARG
	   extract_tracks $SRC_DIR
	   exit 0
	   ;;
	m) make_mkvs
	   exit 0
	   ;;
	e) encode_files
	   exit 0
	   ;;
    esac
done


exit 0

