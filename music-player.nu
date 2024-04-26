# script to play random music

let dirs = (ls z:/flac | where type == dir)

let directory_count = ($dirs | length)

# ideas
# maximum length song
# exclude/include classical/comedy
# dynamic matches on string: artist/album/song
#  with select (using nu table)
# play random albums|artists instead of songs



def get-flac-seconds [
  bytes: binary
  flac_debug?: bool = false
] {
  # https://xiph.org/flac/format.html
  # does it look like a .flac file?
  if ($bytes | bytes starts-with ("fLaC" | into binary)) != true {
    return (-1)
  }

  # verify stream-info block
  let block_header = $bytes | bytes at 4..8 | into int --endian big

  # the first header must be a STREAMINFO header. we don't care about
  # the high order bit (indicating last metadata block) because it's
  # unlikely to be set, but if it is, it doesn't matter - we're not
  # displaying any metadata.
  if ($block_header | bits and 0x7f000000) != 0 {
    return (-1)
  }

  # STREAMINFO headers should be 34 bytes long
  if ($block_header | bits and 0xffffff) != 34 {
    return (-1)
  }

  # byte indexes + STREAMINFO header_base = 8

  # byte index 0
  # <16>	The minimum block size (in samples) used in the stream.
  # byte index 2
  # <16>	The maximum block size (in samples) used in the stream. (Minimum blocksize == maximum blocksize) implies a fixed-blocksize stream.
  # byte index 4
  # <24>	The minimum frame size (in bytes) used in the stream. May be 0 to imply the value is not known.
  # byte index 7
  # <24>	The maximum frame size (in bytes) used in the stream. May be 0 to imply the value is not known.
  # byte index 10
  # <20>	Sample rate in Hz. Though 20 bits are available, the maximum sample rate is limited by the structure of frame headers to 655350Hz. Also, a value of 0 is invalid.
  # <3>	(number of channels)-1. FLAC supports from 1 to 8 channels
  # <5>	(bits per sample)-1. FLAC supports from 4 to 32 bits per sample.
  # <36>	Total samples in stream. 'Samples' means inter-channel sample, i.e. one second of 44.1Khz audio will have 44100 samples regardless of the number of channels. A value of zero here means the number of total samples is unknown.
  # byte index 18
  # <128>	MD5 signature of the unencoded audio data. This allows the decoder to determine if an error exists in the audio data even when the error does not result in an invalid bitstream.
  # NOTES
  # FLAC specifies a minimum block size of 16 and a maximum block size of 65535, meaning the bit patterns corresponding to the numbers 0-15 in the minimum blocksize and maximum blocksize fields are invalid.
  # byte index 34
  # whatever comes next

  # calculate the time using <36> Total samples divided by <20> Sample rate in Hz.
  let sample_bytes = $bytes | bytes at (10 + 8)..(18 + 8)
  let sample_data = $bytes | bytes at (10 + 8)..(18 + 8) | into int --endian big

  let sample_rate = $sample_data | bits shr (64 - 20)
  let bits_per_sample = $sample_data | bits shr 36 | bits and 0x1f | each { |it| $it + 1 }
  let sample_count = $sample_data | bits and 0xfffffffff

  if $flac_debug {
    print $"rate ($sample_rate) count ($sample_count) bits/sample ($bits_per_sample)"
  }

  $sample_count / $sample_rate
}

def main [n: int
  --debug (-d)
] {
  mut x = 0;
  while $x < $n {
    $x = $x + 1
    let r = (random int ..<$directory_count)

    if $debug { print "DEBUG MODE" }

    # get all
    let name = ($dirs | get $r | get name)
    let pattern = $"($name)/**/*.flac"

    # this can fail if there are no .flac files (like willie nelson's mp3s)
    # todo - handle
    let all_flacs = try { ls ($pattern | into glob) }
    if $all_flacs == null {
      print $"no .flac files found for ($name)"
      continue;
    }

    let ix = (random int ..<($all_flacs | length))

    let flac_file_record = ($all_flacs | get $ix)
    if $debug { print $flac_file_record }

    # -wait gives an error.
    #powershell -command $"start-process -wait \"($all_flacs | get $ix | get name)\""
    let flac_name = ($all_flacs | get $ix | get name)

    let bytes = open --raw $'($flac_name)'

    if $debug { print $"bytes length: ($bytes | bytes length)" }

    # calculate number of seconds
    let seconds = get-flac-seconds ($bytes | into binary) $debug

    let raw = $seconds | math round --precision 2
    # make between 1 and 2 seconds longer
    let seconds = ($seconds | math ceil) + 1
    if $debug { print $"calculated wait time ($seconds)" }

    let time = ($"($seconds)sec" | into duration --unit sec)
    let time_text = $"raw ($raw) adjusted: ($seconds) secs \(($time)\)"

    print ($flac_file_record | select name | insert time $"($time_text)")

    # if seconds == (-1) do something - probably skip and issue error msg

    # how to invoke with powershell, but use cross-platform start
    #powershell -command $"start-process \"($flac_name)\""
    start $"($flac_name)"

    sleep ($"($seconds)sec" | into duration)
  }
}

