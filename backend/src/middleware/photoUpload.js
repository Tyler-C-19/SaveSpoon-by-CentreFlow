const multer = require('multer');

const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
const BAD_TYPE = 'Choose a JPEG, PNG or WebP image.';

const parser = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_PHOTO_BYTES, files: 1 },
}).single('photo');

// Checks the file's first bytes rather than the declared type, which phones often leave generic.
function looksLikeImage(buffer) {
  if (!buffer || buffer.length < 12) return false;
  const jpeg = buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
  const png = buffer.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  const webp = buffer.toString('ascii', 0, 4) === 'RIFF' && buffer.toString('ascii', 8, 12) === 'WEBP';
  return jpeg || png || webp;
}

function photoUpload(req, res, next) {
  parser(req, res, (err) => {
    if (err?.code === 'LIMIT_FILE_SIZE') return res.status(400).json({ error: 'Profile picture must be 5 MB or smaller.' });
    if (err) return res.status(400).json({ error: BAD_TYPE });
    if (!req.file || !looksLikeImage(req.file.buffer)) return res.status(400).json({ error: BAD_TYPE });
    return next();
  });
}

module.exports = { photoUpload, looksLikeImage, MAX_PHOTO_BYTES };
