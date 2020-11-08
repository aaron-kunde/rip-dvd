#!/bin/sh

set -e

DVD_DIR=dvd/d
OUT_DIR=out
CMD_MPLAYER="mplayer dvd:// -dvd-device $DVD_DIR"
CMD_MENCODER="mencoder dvd:// -dvd-device $DVD_DIR"


determine_crop() {
    $CMD_MPLAYER -vf cropdetect -vo null
}

audio_tracks() {
    $CMD_MPLAYER -frames 0 -identify 2>/dev/null \
    	| sed -ne 's/ID_AID_\(.\+\)_LANG=\(.\+\)/\1,\2/p'
}

dump_wav() {
    aid=${1}
    wav_file=${2}
    
    $CMD_MPLAYER -ao "pcm:file=$wav_file" -vc dummy -aid $aid -vo null
}

make_ogg() {
    aid=${1}
    lang=${2}
    wav_file=$OUT_DIR/$lang.$id.wav

    dump_wav $id $wav_file
    oggenc -q5 $wav_file
}

dump_audio() {
    to_ogg=${1}
    for track in $(audio_tracks); do
	id=$(echo "$track" | cut -d ',' -f1)
	lang=$(echo "$track" | cut -d ',' -f2)

	if [ $to_ogg ]; then
	    make_ogg $id $lang
	else
	    $CMD_MPLAYER -aid $id -dumpaudio -dumpfile $OUT_DIR/$lang.$id.audio
	fi
    done    
}

subtitle_tracks() {
    $CMD_MPLAYER -frames 0 -identify 2>/dev/null \
	| sed -ne 's/ID_SID_\(.\+\)_LANG=\(.\+\)/\1,\2/p'
}

dump_subtitles() {
    for track in $(subtitle_tracks)
    do
	id=$(echo "$track" | cut -d ',' -f1)
	lang=$(echo "$track" | cut -d ',' -f2)
	$CMD_MENCODER -o /dev/null -nosound -ovc copy \
		      -vobsuboutindex 0 -vobsuboutid $lang -sid $id \
		      -vobsubout $OUT_DIR/$lang.$id
    done    
}

length_s() {
    $CMD_MPLAYER -frames 0 -identify 2>/dev/null | sed -ne 's/ID_LENGTH=//p'
}

bitrate() {
    vid_dst_size_mb=${1}
    length_s=$(length_s)

    echo "$vid_dst_size_mb * 8388.608 / $length_s" | bc
}

encode_video() {
    dst_file=$OUT_DIR/video.x264
    size=${1}
    bitrate=$(bitrate $size)
    filter_crop="crop=${2}"
    # low
    # quality="subq=5:partitions=all:8x8dct:me=umh:frameref=3:bframes=4:b_pyramid=normal:weight_b:bitrate=$bitrate"
    # passes=1
    # high
    passes="1 2"
    
    for pass in $passes
    do
	quality="subq=7:partitions=all:8x8dct:me=umh:frameref=12:bframes=4:b_pyramid=normal:weight_b:pass=$pass:bitrate=$bitrate"
	$CMD_MENCODER -aspect 16/9 -vf $filter_crop -mc 0 \
		      -ovc x264 -x264encopts \
		      $quality \
		      -oac copy -of rawvideo -o $dst_file \
		      -nosub
    done
}

make_mkv() {
    a_file_opts=""

    for f in $(find $OUT_DIR -name '*.audio'); do
	lang=$(echo $(basename $f) | cut -d '.' -f1)
	a_file_opts="$a_file_opts --language 0:$lang $f"
    done

    for f in $(find $OUT_DIR -name '*.ogg'); do
	lang=$(echo $(basename $f) | cut -d '.' -f1)
	a_file_opts="$a_file_opts --language 0:$lang $f"
    done

    s_file_opts=""
    
    for f in $(find $OUT_DIR -name '*.idx'); do
	lang=$(echo $(basename $f) | cut -d '.' -f1)
	s_file_opts="$s_file_opts --language 0:$lang --default-track 0:false -s -0 $f"
    done

    test -f $OUT_DIR/movie.mkv && rm $OUT_DIR/movie.mkv
    mkvmerge -o $OUT_DIR/movie.mkv $OUT_DIR/video.x264 $a_file_opts $s_file_opts
}

while getopts cde:mo opt; do
    case $opt in
	c) sudo mount -t drvfs D: /mnt/d   
	   rm -rf $DVD_DIR
	   cp -r /mnt/d ./dvd
	   exit 0
	   ;;
	d) determine_crop
	   exit 0
	   ;;
	m) make_mkv
	   exit 0
	   ;;
	o) TO_OGG=1
	   ;;
	e) CROP=$OPTARG
	   ;;
    esac
done

test -d $OUT_DIR && rm -rf $OUT_DIR
mkdir $OUT_DIR
dump_audio $TO_OGG
dump_subtitles
encode_video 700 $CROP
exit 0


