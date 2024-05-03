// C:\Users\xxxxx\AppData\Roaming\Microsoft\Windows\Libraries
// supposedly controlled by: HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders
// https://www.tenforums.com/general-support/138108-actual-location-my-library-folders-files-my-user-directory.html

const fs = require('fs');
const path = require('path');

const dirs = [
  'Z:\\FLAC\\Leonard Bernstein & The New York Philharmonic',
  'Z:\\FLAC\\Jon Nakamatsu',
  'Z:\\FLAC\\Academy of St. Martin-In-The-Fields',
  'Z:\\FLAC\\Antonio Vivaldi',
  'Z:\\FLAC\\Carlos Paredes',
  'Z:\\FLAC\\Celedonio Romero',
  'Z:\\FLAC\\Cincinnati Pops, Erich Kunzel',
  'Z:\\FLAC\\Clara Rockmore',
  'Z:\\FLAC\\Elvis Costello\\Il Sogno-London Symphony, Michael Til',
  'Z:\\FLAC\\Ensemble Modern Plays Frank Zappa',
  'Z:\\FLAC\\György Cziffra',
  'Z:\\FLAC\\Heiki Mätlik',
  'Z:\\FLAC\\Helmuth Rilling',
  'Z:\\FLAC\\Jascha Heifetz',
  'Z:\\FLAC\\Jean Sibelius',
  'Z:\\FLAC\\Jean-Pierre Rampal',
  'Z:\\FLAC\\Los Romeros',
  'Z:\\FLAC\\Luba Orgonasova',
  'Z:\\FLAC\\Maxim Vengerov',
  'Z:\\FLAC\\Narciso Yepes',
  'Z:\\FLAC\\Pau Casals',
  'Z:\\FLAC\\Pepe Romero',
  'Z:\\FLAC\\Ute Lemper',
  'Z:\\FLAC\\Wu Man',
  'Z:\\FLAC\\Xuefei Yang',
  'Z:\\FLAC\\Alexandre Lagoya',
  'Z:\\FLAC\\Maurice Ravel',
];

const FLAC = Buffer.from('fLaC');

const BLOCK_TYPES = {
  0: 'STREAMINFO',
  1: 'PADDING',
  2: 'APPLICATION',
  3: 'SEEKTABLE',
  4: 'VORBIS_COMMENT',
  5: 'CUESHEET',
  6: 'PICTURE',
  127: 'invalid',
};

function getBlockName(code) {
  if (code in BLOCK_TYPES) {
    return BLOCK_TYPES[code];
  }
  return 'reserved';
}

let genres = {};
let outliers = {};

for (const dir of dirs) {
  const files = fs.readdirSync(dir, {recursive: true, withFileTypes: true});
  const flacs = files.filter(file => file.isFile() && file.name.endsWith('.flac'));

  for (const flac of flacs) {
    const file = path.join(flac.path, flac.name);
    const genre = getGenre(file);
    if (genre in genres) {
      genres[genre] += 1;
    } else {
      genres[genre] = 1;
    }
    if (genre !== 'Classical') {
      // capture albums
      let album = path.dirname(flac.path);

      if (genre in outliers) {
        outliers[genre].push(album);
      } else {
        outliers[genre] = [album];
      }
    }
  }
}


console.log(outliers);
console.log(genres);

function getGenre(file) {
  console.log('reading', file);
  const bytes = fs.readFileSync(file);

  if (FLAC.compare(bytes, 0, FLAC.length) != 0) {
    return 'not-a-flac-file';
  }

  let currentBase = 4; // skip the 'fLaC' signature

  let blockHeader = bytes.readInt32BE(currentBase);
  let blockType = blockHeader >>> 24 & 0x7f;
  let blockLength = blockHeader & 0xffffff;
  let lastMetadataHeader = blockHeader & 0x80000000;

  if (blockType !== 0) {
    // STREAMINFO must be first, so this is a problem.
    return 'streaminfo-not-first-metadata';
  }

  // skip streaminfo for now; just care about vorbis comments
  currentBase += blockLength + 4;

  // maybe need to check for buffer length too for malformed flac files
  while (!lastMetadataHeader) {
    blockHeader = bytes.readInt32BE(currentBase);
    blockType = blockHeader >>> 24 & 0x7f;
    blockLength = blockHeader & 0xffffff;
    lastMetadataHeader = blockHeader & 0x80000000;
    // skip the header
    currentBase += 4;

    if (getBlockName(blockType) === 'VORBIS_COMMENT') {
      const comments = getComments(bytes.subarray(currentBase));
      for (const comment of comments) {
        if (comment.startsWith('Genre=') || comment.startsWith('genre=')) {
          return comment.split('=')[1];
        }
      }
    }

    // skip the rest of the block, if any
    currentBase += blockLength;
  }

  return 'no-genre-found';
}

//# The comment header is decoded as follows:
//# 1)[vendor_length] = read an unsigned integer of 32 bits
//# 2)[vendor_string] = read a UTF - 8 vector as [vendor_length] octets
//# 3)[user_comment_list_length] = read an unsigned integer of 32 bits
//# 4) iterate[user_comment_list_length] times {
//    #  5)[length] = read an unsigned integer of 32 bits
//    #  6) this iteration's user comment = read a UTF-8 vector as [length] octets
//# }
//# 7)[framing_bit] = read a single bit as boolean
//# 8) if ([framing_bit] unset or end of packet ) then ERROR
//# 9) done
function getComments(bytes) {
  const comments = [];
  let base = 0;
  let vendorStringLength = bytes.readInt32LE(0);
  base += 4;
  let vendorString = bytes.toString('utf-8', base, base + vendorStringLength);
  base += vendorStringLength;
  let commentCount = bytes.readInt32LE(base);
  base += 4;
  for (let i = 0; i < commentCount; i++) {
    const commentLength = bytes.readInt32LE(base);
    base += 4;
    const comment = bytes.toString('utf-8', base, base + commentLength);
    base += commentLength;
    comments.push(comment);
  }
  return comments.length ? comments : null;
}
