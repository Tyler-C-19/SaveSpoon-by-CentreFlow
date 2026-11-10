// These tests replace Cloudinary and database calls with mocks and never connect to the shared database.
const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');

const { query, call } = require('./testServer');
const User = require('../src/models/User');
const Vendor = require('../src/models/Vendor');
const photoService = require('../src/services/photoService');
const { looksLikeImage } = require('../src/middleware/photoUpload');
const { signToken } = require('../src/services/tokenService');

const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(32)]);
const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(32)]);
const WEBP = Buffer.concat([Buffer.from('RIFF'), Buffer.alloc(4), Buffer.from('WEBP'), Buffer.alloc(32)]);

let uploads;
let removed;

function signedInAs(user) {
  mock.method(User, 'findById', () => query(user));
  mock.method(User, 'exists', async () => null);
  return signToken(user.id);
}

const makeUser = (extra = {}) =>
  new User({ name: 'Test', email: 'c@example.com', role: 'customer', emailVerified: true, ...extra });

function photoForm(buffer, type = 'image/png', name = 'photo.png', crop = null) {
  const form = new FormData();
  form.append('photo', new Blob([buffer], { type }), name);
  if (crop) {
    form.append('cropX', String(crop.x));
    form.append('cropY', String(crop.y));
    form.append('cropWidth', String(crop.width));
    form.append('cropHeight', String(crop.height));
  }
  return form;
}

let framed;

beforeEach(() => {
  mock.restoreAll();
  uploads = [];
  removed = [];
  mock.method(User.prototype, 'save', async function save() { return this; });
  mock.method(Vendor, 'findOne', async () => null);
  mock.method(photoService, 'isConfigured', () => true);
  framed = [];
  mock.method(photoService, 'upload', async (buffer) => {
    uploads.push(buffer);
    return {
      id: 'savespoon/profile-photos/new',
      originalUrl: 'https://res.cloudinary.com/demo/original.jpg',
      width: 1000,
      height: 800,
    };
  });
  mock.method(photoService, 'framedUrl', (original, crop) => {
    framed.push({ original, crop });
    return `https://res.cloudinary.com/demo/framed-${crop.x}.jpg`;
  });
  mock.method(photoService, 'remove', async (id) => removed.push(id));
  mock.method(console, 'error', () => {});
});

test('uploading a photo saves its address and deletes the old one', async () => {
  const user = makeUser({ photoUrl: 'https://old', photoId: 'old-id' });
  const token = signedInAs(user);

  const res = await call('/api/users/me/photo', { method: 'PUT', token, form: photoForm(PNG) });

  assert.equal(res.status, 200);
  assert.equal(res.body.user.photoUrl, 'https://res.cloudinary.com/demo/framed-0.jpg');
  assert.equal(res.body.user.photoOriginalUrl, 'https://res.cloudinary.com/demo/original.jpg');
  assert.deepEqual(res.body.user.photoCrop, { x: 0, y: 0, width: 1, height: 1 });
  for (const hidden of ['photoId', 'photoWidth', 'photoHeight']) assert.equal(hidden in res.body.user, false);
  assert.equal(user.photoId, 'savespoon/profile-photos/new');
  assert.equal(uploads.length, 1);
  assert.deepEqual(removed, ['old-id']);
});

test('the chosen framing is saved with the upload', async () => {
  const user = makeUser();
  const token = signedInAs(user);
  const crop = { x: 0.1, y: 0, width: 0.8, height: 1 };

  const res = await call('/api/users/me/photo', { method: 'PUT', token, form: photoForm(PNG, 'image/png', 'p.png', crop) });

  assert.equal(res.status, 200);
  assert.deepEqual(framed[0], {
    original: { id: 'savespoon/profile-photos/new', width: 1000, height: 800 },
    crop,
  });
  assert.deepEqual(res.body.user.photoCrop, crop);
});

for (const [name, crop] of [
  ['outside the picture', { x: 0.5, y: 0, width: 0.8, height: 1 }],
  ['negative', { x: -0.1, y: 0, width: 0.5, height: 0.5 }],
  ['too small', { x: 0, y: 0, width: 0.001, height: 0.001 }],
]) {
  test(`a framing ${name} is rejected before uploading`, async () => {
    const token = signedInAs(makeUser());
    const res = await call('/api/users/me/photo', { method: 'PUT', token, form: photoForm(PNG, 'image/png', 'p.png', crop) });
    assert.equal(res.status, 400);
    assert.equal(uploads.length, 0);
  });
}

test('framing the current pic again needs no upload', async () => {
  const user = makeUser({
    photoUrl: 'https://old', photoId: 'old-id', photoOriginalUrl: 'https://orig', photoWidth: 600, photoHeight: 900,
  });
  const token = signedInAs(user);
  const crop = { x: 0, y: 0.2, width: 1, height: 0.6 };

  const res = await call('/api/users/me/photo', { method: 'PATCH', token, body: { crop } });

  assert.equal(res.status, 200);
  assert.equal(uploads.length, 0);
  assert.deepEqual(removed, []);
  assert.deepEqual(framed[0].original, { id: 'old-id', width: 600, height: 900 });
  assert.equal(user.photoUrl, 'https://res.cloudinary.com/demo/framed-0.jpg');
});

test('framing again without a pic returns 404', async () => {
  const token = signedInAs(makeUser());
  const res = await call('/api/users/me/photo', {
    method: 'PATCH', token, body: { crop: { x: 0, y: 0, width: 1, height: 1 } },
  });
  assert.equal(res.status, 404);
});

for (const [name, buffer, type] of [['JPEG', JPEG, 'image/jpeg'], ['WebP', WEBP, 'image/webp']]) {
  test(`a ${name} photo is accepted`, async () => {
    const token = signedInAs(makeUser());
    const res = await call('/api/users/me/photo', { method: 'PUT', token, form: photoForm(buffer, type) });
    assert.equal(res.status, 200);
  });
}

test('a file that is not an image is rejected, even with an image type', async () => {
  const token = signedInAs(makeUser());

  const res = await call('/api/users/me/photo', {
    method: 'PUT', token, form: photoForm(Buffer.from('not really a picture at all'), 'image/png'),
  });

  assert.equal(res.status, 400);
  assert.equal(uploads.length, 0);
});

test('a GIF is rejected', async () => {
  const token = signedInAs(makeUser());
  const res = await call('/api/users/me/photo', {
    method: 'PUT', token, form: photoForm(Buffer.from('GIF89a......'), 'image/gif', 'a.gif'),
  });
  assert.equal(res.status, 400);
  assert.equal(uploads.length, 0);
});

test('a photo over 5 MB is rejected', async () => {
  const token = signedInAs(makeUser());
  const big = Buffer.concat([PNG, Buffer.alloc(5 * 1024 * 1024)]);

  const res = await call('/api/users/me/photo', { method: 'PUT', token, form: photoForm(big) });

  assert.equal(res.status, 400);
  assert.match(res.body.error, /5 MB/);
  assert.equal(uploads.length, 0);
});

test('a missing photo is rejected', async () => {
  const token = signedInAs(makeUser());
  const res = await call('/api/users/me/photo', { method: 'PUT', token, form: new FormData() });
  assert.equal(res.status, 400);
});

test('without Cloudinary keys the upload says photos are unavailable', async () => {
  const user = makeUser();
  const token = signedInAs(user);
  photoService.isConfigured.mock.mockImplementation(() => false);

  const res = await call('/api/users/me/photo', { method: 'PUT', token, form: photoForm(PNG) });

  assert.equal(res.status, 503);
  assert.equal(res.body.code, 'PHOTOS_UNAVAILABLE');
  assert.equal(user.photoUrl, undefined);
});

test('a failed upload keeps the old photo', async () => {
  const user = makeUser({ photoUrl: 'https://old', photoId: 'old-id' });
  const token = signedInAs(user);
  photoService.upload.mock.mockImplementation(async () => { throw new photoService.PhotoError('down'); });

  const res = await call('/api/users/me/photo', { method: 'PUT', token, form: photoForm(PNG) });

  assert.equal(res.status, 503);
  assert.equal(user.photoUrl, 'https://old');
  assert.deepEqual(removed, []);
});

test('removing the photo clears it and deletes the file', async () => {
  const user = makeUser({ photoUrl: 'https://old', photoId: 'old-id' });
  const token = signedInAs(user);

  const res = await call('/api/users/me/photo', { method: 'DELETE', token });

  assert.equal(res.status, 200);
  assert.equal(user.photoUrl, undefined);
  assert.equal(user.photoOriginalUrl, undefined);
  assert.deepEqual(removed, ['old-id']);
});

test('uploads and reframes share a limit of 10 a day, and removing still works', async () => {
  const user = makeUser();
  const token = signedInAs(user);
  const reframe = { method: 'PATCH', token, body: { crop: { x: 0, y: 0, width: 1, height: 1 } } };

  for (let i = 0; i < 9; i += 1) {
    assert.equal((await call('/api/users/me/photo', { method: 'PUT', token, form: photoForm(PNG) })).status, 200);
  }
  assert.equal((await call('/api/users/me/photo', reframe)).status, 200);

  const res = await call('/api/users/me/photo', { method: 'PUT', token, form: photoForm(PNG) });
  assert.equal(res.status, 429);
  assert.match(res.body.error, /10 times today/);
  assert.equal(uploads.length, 9);
  assert.equal((await call('/api/users/me/photo', reframe)).status, 429);
  assert.equal((await call('/api/users/me/photo', { method: 'DELETE', token })).status, 200);
});

test('the image check knows JPEG, PNG and WebP only', () => {
  assert.equal(looksLikeImage(PNG), true);
  assert.equal(looksLikeImage(JPEG), true);
  assert.equal(looksLikeImage(WEBP), true);
  assert.equal(looksLikeImage(Buffer.from('GIF89a......')), false);
  assert.equal(looksLikeImage(Buffer.alloc(3)), false);
});

test('the photo service refuses to run without keys', async () => {
  const saved = ['CLOUDINARY_CLOUD_NAME', 'CLOUDINARY_API_KEY', 'CLOUDINARY_API_SECRET'].map((k) => [k, process.env[k]]);
  saved.forEach(([k]) => delete process.env[k]);
  photoService.isConfigured.mock.restore();
  photoService.upload.mock.restore();

  assert.equal(photoService.isConfigured(), false);
  await assert.rejects(photoService.upload(PNG), photoService.PhotoError);

  saved.forEach(([k, v]) => { if (v !== undefined) process.env[k] = v; });
});
