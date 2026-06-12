const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const { Pool } = require('pg');
const redis = require('redis');

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware
app.use(helmet());
app.use(cors({ origin: process.env.FRONTEND_URL || '*' }));
app.use(morgan('combined'));
app.use(express.json());

// PostgreSQL Connection
const pool = new Pool({
  host: process.env.DB_HOST || 'postgres',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'bookmyshow',
  user: process.env.DB_USER || 'admin',
  password: process.env.DB_PASSWORD || 'admin123',
});

// Redis Connection
let redisClient;
(async () => {
  redisClient = redis.createClient({
    url: `redis://${process.env.REDIS_HOST || 'redis'}:${process.env.REDIS_PORT || 6379}`,
  });
  redisClient.on('error', (err) => console.log('Redis Client Error', err));
  await redisClient.connect();
  console.log('✅ Redis connected');
})();

// DB Health check + init
pool.query('SELECT NOW()', (err) => {
  if (err) console.error('❌ PostgreSQL connection error:', err);
  else console.log('✅ PostgreSQL connected');
});

// ─── Routes ───────────────────────────────────────────────

// Health
app.get('/api/health', async (req, res) => {
  let dbOk = false, cacheOk = false;
  try { await pool.query('SELECT 1'); dbOk = true; } catch {}
  try { await redisClient.ping(); cacheOk = true; } catch {}
  res.json({ status: 'ok', database: dbOk ? 'connected' : 'error', cache: cacheOk ? 'connected' : 'error', timestamp: new Date() });
});

// Movies
app.get('/api/movies', async (req, res) => {
  try {
    const cached = await redisClient.get('movies:all');
    if (cached) return res.json({ source: 'cache', data: JSON.parse(cached) });
    const result = await pool.query('SELECT * FROM movies ORDER BY release_date DESC');
    await redisClient.setEx('movies:all', 300, JSON.stringify(result.rows));
    res.json({ source: 'db', data: result.rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/movies/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const cached = await redisClient.get(`movie:${id}`);
    if (cached) return res.json({ source: 'cache', data: JSON.parse(cached) });
    const result = await pool.query('SELECT * FROM movies WHERE id = $1', [id]);
    if (!result.rows.length) return res.status(404).json({ error: 'Movie not found' });
    await redisClient.setEx(`movie:${id}`, 300, JSON.stringify(result.rows[0]));
    res.json({ source: 'db', data: result.rows[0] });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Shows / Screenings
app.get('/api/movies/:id/shows', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT s.*, t.name as theatre_name, t.city, t.address 
       FROM screenings s JOIN theatres t ON s.theatre_id = t.id 
       WHERE s.movie_id = $1 AND s.show_time > NOW() ORDER BY s.show_time`,
      [req.params.id]
    );
    res.json({ data: result.rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Theatres
app.get('/api/theatres', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM theatres ORDER BY city, name');
    res.json({ data: result.rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Seats
app.get('/api/screenings/:screeningId/seats', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM seats WHERE screening_id = $1 ORDER BY row_label, seat_number',
      [req.params.screeningId]
    );
    res.json({ data: result.rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Bookings
app.post('/api/bookings', async (req, res) => {
  const client = await pool.connect();
  try {
    const { screening_id, seat_ids, user_name, user_email, total_amount } = req.body;
    await client.query('BEGIN');

    // Lock seats
    const seatCheck = await client.query(
      'SELECT * FROM seats WHERE id = ANY($1) AND screening_id = $2 AND is_booked = false FOR UPDATE',
      [seat_ids, screening_id]
    );
    if (seatCheck.rows.length !== seat_ids.length) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'One or more seats already booked' });
    }

    const booking = await client.query(
      `INSERT INTO bookings (screening_id, user_name, user_email, seat_ids, total_amount, booking_ref)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [screening_id, user_name, user_email, seat_ids, total_amount, `BMS-${Date.now()}`]
    );
    await client.query('UPDATE seats SET is_booked = true WHERE id = ANY($1)', [seat_ids]);
    await client.query('COMMIT');

    // Invalidate cache
    await redisClient.del('movies:all');

    res.status(201).json({ data: booking.rows[0] });
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(500).json({ error: err.message });
  } finally {
    client.release();
  }
});

app.get('/api/bookings/:ref', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT b.*, s.show_time, m.title as movie_title, t.name as theatre_name
       FROM bookings b 
       JOIN screenings s ON b.screening_id = s.id
       JOIN movies m ON s.movie_id = m.id
       JOIN theatres t ON s.theatre_id = t.id
       WHERE b.booking_ref = $1`,
      [req.params.ref]
    );
    if (!result.rows.length) return res.status(404).json({ error: 'Booking not found' });
    res.json({ data: result.rows[0] });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 404 fallback
app.use((req, res) => res.status(404).json({ error: 'Route not found' }));

app.listen(PORT, () => console.log(`🚀 BookMyShow API running on port ${PORT}`));

module.exports = app;
