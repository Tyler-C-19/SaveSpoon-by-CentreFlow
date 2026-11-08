const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const mongoose = require('mongoose');
const app = require('./app');

const PORT = process.env.PORT || 5000;

// Hosts such as Render sit behind one proxy, so the client's IP comes from its header.
app.set('trust proxy', 1);

const missing = ['MONGODB_URI', 'JWT_SECRET', 'EMAIL_USER', 'EMAIL_APP_PASSWORD', 'GOOGLE_CLIENT_ID'].filter((key) => !process.env[key]);
if (missing.length) {
  console.error(`Missing from backend/.env: ${missing.join(', ')}`);
  process.exit(1);
}

mongoose
  .connect(process.env.MONGODB_URI)
  .then(() => {
    console.log('MongoDB connected');
    app.listen(PORT, () => console.log(`API running on port ${PORT}`));
  })
  .catch((err) => {
    console.error('Could not connect to MongoDB:', err.message);
    process.exitCode = 1;
  });
