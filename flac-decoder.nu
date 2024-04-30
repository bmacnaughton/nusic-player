#!/usr/bin/env nu

export def decode-flac [file: string] {
  main $file
}


def main [
  file: string
  --debug (-d)
] {
  let bytes = open --raw $file

  # https://xiph.org/flac/format.html
  # does it look like a .flac file?
  if ($bytes | bytes starts-with ("fLaC" | into binary)) != true {
    return (-1)
  }

  mut headers = []

  # first byte of next block
  mut block_index = 4

  # verify stream-info block

  mut n = 0;

  loop {
    mut block_header = $bytes | bytes at $block_index..($block_index + 4) | into int --endian big

    let block_type = $block_header | bits shr 24 -n 4 | bits and 0x7f
    let block = match $block_type {
      0 => {
        { name: "STREAMINFO", contents: (decode_streaminfo $bytes ($block_index + 4)) }
      },
      1 => {
        { name: "PADDING", contents: [] }
      },
      2 => { name: "APPLICATION", contents: [] },
      3 => { name: "SEEKTABLE", contents: [] },
      4 => {
        { name: "VORBIS_COMMENT", contents: (decode_vorbis_comment $bytes ($block_index + 4)) }
      }
      5 => { name: "CUESHEET", contents: [] },
      6 => { name: "PICTURE", contents: [] },
      127 => { name: "invalid", contents: [] },
      _ => { name: "reserved" contents: [] },
    }
    let block_length = $block_header | bits and 0xffffff

    $headers = ($headers | append {
      type: $block.name,
      contents: $block.contents,
      raw: {
        header: ($block_header | fmt | get lowerhex),
        length: ($block_header | bits and 0xffffff),
      }
    })

    # if the high order bit is set this is the last header
    if ($block_header | bits and 0x80000000) != 0 {
      if $debug {
        print $"last header ($block_header | fmt | get lowerhex)"
      }
      break
    }

    $n += 1
    if $n > 10 {
      break
    }

    # skip to next block (header bytes + block bytes)
    $block_index += 4 + $block_length
  }

  $headers
}

def decode_streaminfo [
  bytes: binary
  base: int
  --debug (-d)
 ] {
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
  if $debug {
    print $"decoding with base ($base)"
  }

  let sample_data_64 = $bytes | bytes at ($base + 10)..($base + 18) | into int --endian big
  let sample_rate = $sample_data_64 | bits shr (64 - 20)
  let bits_per_sample = $sample_data_64 | bits shr 36 | bits and 0x1f
  let sample_count = $sample_data_64 | bits and 0xfffffffff

  # time in seconds == $sample_count / $sample_rate

  { sample_rate: $sample_rate bits_per_sample: ($bits_per_sample + 1) sample_count: $sample_count }
}

def decode_vorbis_comment [
  bytes: binary
  base: int
  --debug (-d)
] {
  # NOTE: the 32-bit field lengths are little-endian coded according to the vorbis spec, as opposed to the usual
  # big-endian coding of fixed-length integers in the rest of FLAC.

  # https://www.xiph.org/vorbis/doc/v-comment.html
  # The comment header logically is a list of eight-bit-clean vectors; the number of vectors is bounded to 2^32-1 and the length of each vector is limited to 2^32-1 bytes. The vector length is encoded; the vector contents themselves are not null terminated. In addition to the vector list, there is a single vector for vendor name (also 8 bit clean, length encoded in 32 bits). For example, the 1.0 release of libvorbis set the vendor string to "Xiph.Org libVorbis I 20020717".

  # The comment header is decoded as follows:
    # 1) [vendor_length] = read an unsigned integer of 32 bits
    # 2) [vendor_string] = read a UTF-8 vector as [vendor_length] octets
    # 3) [user_comment_list_length] = read an unsigned integer of 32 bits
    # 4) iterate [user_comment_list_length] times {
        #  5) [length] = read an unsigned integer of 32 bits
        #  6) this iteration's user comment = read a UTF-8 vector as [length] octets
    #  }
    # 7) [framing_bit] = read a single bit as boolean
    # 8) if ( [framing_bit] unset or end of packet ) then ERROR
    # 9) done
    mut comments = []

    let vendor_length = $bytes | bytes at $base..($base + 4) | into int --endian little
    mut current = $base + 4
    let vendor_string = $bytes | bytes at ($current)..($current + $vendor_length) | decode utf-8
    $current += $vendor_length

    let comment_count = $bytes | bytes at $current..($current + 4) | into int --endian little
    $current += 4;

    for _ in 0..<$comment_count {
      let comment_length = $bytes | bytes at $current..($current + 4) | into int --endian little
      $current += 4
      let comment_string = $bytes | bytes at $current..($current + $comment_length) | decode utf-8
      $current += $comment_length

      $comments = ($comments | append $comment_string)
    }

    # check framing bit for fun. standard says "read single bit" and that's what the
    # code looks like, but comments have to end on a byte boundary, so "what is the
    # next bit" for vorbis comments. idk. not sure it matters much.
    if $debug {
      let framing_bit = $bytes | bytes at $current..($current + 1) | into int --endian little
      print $"framing_bit ($framing_bit)"
    }

    # return { key, value } records with lowercase key
    $comments | parse "{key}={value}" | each {
      |it| {key: ($it.key | str downcase), value: $it.value }
    }
}
